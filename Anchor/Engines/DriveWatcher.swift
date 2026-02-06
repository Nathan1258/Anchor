//
//  DriveWatcher.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import SwiftUI
import Combine
import Cocoa

class DriveWatcher: NSObject, ObservableObject, NSFilePresenter {
    
    @Published var sourceURL: URL?
    @Published var vaultURL: URL?
    @Published var isRunning = false
    
    @Published var status: DriveStatus = .idle
    @Published var isScanning: Bool = false
    @Published var lastSyncTime: Date? = nil
    
    @Published var sessionScannedCount: Int = 0
    @Published var sessionVaultedCount: Int = 0
    @Published var lastFileProcessed: String = "-"
    
    @Published var logs: [LogEntry] = []
    
    private let ledger = SQLiteLedger()
    private var vaultProvider: VaultProvider?
    private var vaultMonitor: VaultMonitor?
    private var cancellables = Set<AnyCancellable>()
    
    private var debounceTasks: [URL: DispatchWorkItem] = [:]
    
    override init() {
        super.init()
        restoreState()
        setupPauseObserver()
        setupNetworkObserver()
    }
    
    private func setupPauseObserver() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                if !PersistenceManager.shared.isGlobalPaused && self?.status == .paused {
                    self?.log("▶️ Global pause expired. Resuming...")
                    self?.startWatching()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupNetworkObserver() {
        NetworkMonitor.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                
                if status == .verified {
                    if self.status == .paused {
                        self.log("✅ Internet restored. Resuming...")
                        self.startWatching()
                    }
                } else if status == .disconnected || status == .captivePortal {
                    self.log("⚠️ Network issue detected. Pausing Watcher.")
                    self.status = .paused
                }
            }
            .store(in: &cancellables)
    }
    
    private func restoreState() {
        if let source = PersistenceManager.shared.loadBookmark(type: .driveSource) {
            if source.startAccessingSecurityScopedResource() {
                self.sourceURL = source
            }
        }
        
        if PersistenceManager.shared.driveVaultType == .local,
           let vault = PersistenceManager.shared.loadBookmark(type: .driveVault),
           vault.startAccessingSecurityScopedResource(){
            self.vaultURL = vault
        }
        
        if sourceURL != nil {
            let isLocalReady = (PersistenceManager.shared.driveVaultType == .local && vaultURL != nil)
            let isS3Ready = (PersistenceManager.shared.driveVaultType == .s3 && PersistenceManager.shared.s3Config.isValid)
            
            if isLocalReady || isS3Ready {
                log("♻️ Restored previous session. Auto-starting...")
                startWatching()
            }
        }
    }
    
    var presentedItemURL: URL? { return sourceURL }
    
    lazy var presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    func presentedSubitemDidAppear(at url: URL) {
        if PersistenceManager.shared.isGlobalPaused {
            DispatchQueue.main.async { self.status = .paused }
            return
        }
        guard PersistenceManager.shared.isDriveEnabled else { return }
        
        DispatchQueue.main.async { self.status = .newItem }
        log("✨ New Item Detected: \(url.lastPathComponent)")
        debounceFileEvent(at: url)
    }
    
    func presentedSubitemDidChange(at url: URL) {
        if PersistenceManager.shared.isGlobalPaused {
            DispatchQueue.main.async { self.status = .paused }
            return
        }
        guard PersistenceManager.shared.isDriveEnabled else { return }
        
        DispatchQueue.main.async { self.status = .changeDetected }
        log("Hz Change Detected: \(url.lastPathComponent)")
        debounceFileEvent(at: url)
    }
    
    private func debounceFileEvent(at url: URL) {
        if let existingTask = debounceTasks[url] {
            existingTask.cancel()
        }
        
        let task = DispatchWorkItem { [weak self] in
            self?.debounceTasks.removeValue(forKey: url)
            self?.handleIncomingFile(at: url)
        }
        
        debounceTasks[url] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }
    
    func pickNewVaultFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select New Vault"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url)
            }
        }
    }
    
    func applyVaultSwitch(type: VaultType? = nil, url: URL? = nil) {
        self.status = .idle
        self.isRunning = false
        
        ledger.wipe()
        self.sessionScannedCount = 0
        self.sessionVaultedCount = 0
        
        if let newType = type {
            PersistenceManager.shared.driveVaultType = newType
        }
        
        if let newUrl = url {
            self.vaultURL = newUrl
            PersistenceManager.shared.saveBookmark(for: newUrl, type: .driveVault)
        }
        
        log("🔄 Vault switched. Starting fresh scan...")
        startWatching()
    }
    
    func reconcileMirrorMode(strict: Bool) {
        guard strict else {
            log("ℹ️ Switched to Mirror Mode. Only future deletions will be synced.")
            return
        }
        
        guard let source = sourceURL else { return }
        
        Task {
            self.status = .scanning
            log("🧹 Starting Reconciliation Scan (Strict Mirror)...")
            
            let trackedFiles = ledger.getAllTrackedPaths()
            var deletedCount = 0
            
            for relativePath in trackedFiles {
                let sourceFile = source.appendingPathComponent(relativePath)
                
                if !FileManager.default.fileExists(atPath: sourceFile.path) {
                    log("🗑️ Found orphan: \(relativePath). Deleting from Vault...")
                    
                    self.deleteFromVault(relativePath: relativePath)
                    deletedCount += 1
                }
            }
            
            DispatchQueue.main.async {
                self.status = .idle
                if deletedCount > 0 {
                    self.log("✅ Reconciliation Complete. Removed \(deletedCount) old files from Vault.")
                } else {
                    self.log("✅ Reconciliation Complete. Vault perfectly matches Source.")
                }
            }
        }
    }
    
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        if PersistenceManager.shared.isGlobalPaused { return }
        
        if ExclusionManager.shared.shouldIgnore(url: newURL) { return }
        
        guard let oldRelative = getRelativePath(for: oldURL),
              let newRelative = getRelativePath(for: newURL) else { return }
        
        log("🚚 Detected Move: \(oldRelative) -> \(newRelative)")
        
        ledger.renamePath(from: oldRelative, to: newRelative)
        
        Task {
            do {
                try await vaultProvider?.moveItem(from: oldRelative, to: newRelative)
                self.status = .active
            } catch {
                log("⚠️ Failed to move in Vault: \(error.localizedDescription)")
                self.handleIncomingFile(at: newURL)
            }
        }
    }
    
    private func getRelativePath(for url: URL) -> String? {
        guard let source = sourceURL else { return nil }
        let filePath = url.path
        let sourcePath = source.path
        if !filePath.hasPrefix(sourcePath) { return nil }
        var relative = String(filePath.dropFirst(sourcePath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
    
    private func handleIncomingFile(at url: URL) {
        guard !PersistenceManager.shared.isGlobalPaused,
              PersistenceManager.shared.isDriveEnabled else { return }
        
        if !FileManager.default.fileExists(atPath: url.path) {
            if PersistenceManager.shared.backupMode == .mirror {
                guard let relativePath = getRelativePath(for: url) else { return }
                deleteFromVault(relativePath: relativePath)
            } else {
                log("🗑️ File deleted in Cloud. Kept in Vault (Safety Net).")
            }
            return
        }
        
        guard let metadata = extractMetadata(for: url),
              !ExclusionManager.shared.shouldIgnore(url: url)
        else { return }
        
        if ledger.shouldProcess(relativePath: metadata.relativePath, currentGenID: metadata.genID) {
            processFile(at: url, genID: metadata.genID, relativePath: metadata.relativePath)
        } else {
            DispatchQueue.main.async { self.status = .monitoring }
        }
    }
    
    private func cleanupStaleUploads() {
        guard let s3Vault = vaultProvider as? S3Vault,
              let source = sourceURL else { return }
        
        Task {
            let activeUploads = ledger.getAllActiveUploads()
            if activeUploads.isEmpty { return }
            
            log("🧹 Checking \(activeUploads.count) pending uploads for staleness...")
            
            var cleanedCount = 0
            
            for upload in activeUploads {
                let fileURL = source.appendingPathComponent(upload.relativePath)
                
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    log("🗑️ Orphan detected: \(upload.relativePath). Aborting S3 fragments...")
                    
                    do {
                        try await s3Vault.abortUpload(key: upload.relativePath, uploadId: upload.uploadID)
                        ledger.removeUploadID(relativePath: upload.relativePath)
                        cleanedCount += 1
                    } catch {
                        log("⚠️ Failed to clean orphan: \(error.localizedDescription)")
                    }
                }
            }
            
            if cleanedCount > 0 {
                log("✨ Cleaned up \(cleanedCount) incomplete uploads.")
            }
        }
    }
    
    private func deleteFromVault(relativePath: String) {
        guard let provider = vaultProvider else { return }
        
        Task{
            do{
                try await provider.deleteFile(relativePath: relativePath)
                ledger.removeEntry(relativePath: relativePath)
                
                log("🗑️ Synced Deletion: \(relativePath)")
                DispatchQueue.main.async {
                    self.status = .deleted(filename: (relativePath as NSString).lastPathComponent)
                }
            } catch {
                log("⚠️ Failed to delete vault copy: \(error.localizedDescription)")
            }
        }
    }
    
    func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = "Anchor needs permission to watch your iCloud Drive."
        
        if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            panel.directoryURL = iCloudURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let standardPath = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            panel.directoryURL = standardPath
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.sourceURL = url
                PersistenceManager.shared.saveBookmark(for: url, type: .driveSource)
                self.log("Source set to: \(url.path)")
            }
        }
    }
    
    func selectVaultFolder() {
        requestFolderAccess(prompt: "Select Backup Vault") { url in
            self.vaultURL = url
            PersistenceManager.shared.saveBookmark(for: url, type: .driveVault)
            self.log("Vault set to: \(url.path)")
            
            if self.sourceURL != nil { self.startWatching() }
        }
    }
    
    func startWatching() {
        guard !PersistenceManager.shared.isGlobalPaused else {
            log("Global Pause Active. Watcher standing by.")
            self.status = .paused
            return
        }
        
        guard PersistenceManager.shared.isDriveEnabled else {
            log("🚫 Drive Sync is disabled in Settings.")
            self.status = .disabled
            return
        }
        
        guard let source = sourceURL else {
            log("❌ Error: Select both folders first.")
            return
        }
        
        if !source.startAccessingSecurityScopedResource() {
            log("❌ Failed to access source folder. Check Permissions.")
            return
        }
        
        self.status = .waitingForVault
        
        if !source.startAccessingSecurityScopedResource() {
            log("❌ Failed to access source folder. Check Permissions.")
            return
        }
        
        Task {
            let type = PersistenceManager.shared.driveVaultType
            
            do {
                guard let provider = try await VaultFactory.getProvider(type: type) else {
                    DispatchQueue.main.async {
                        self.log("❌ Error: Could not initialize Vault Provider. Check Settings.")
                        self.status = .disabled
                    }
                    return
                }
                
                self.vaultProvider = provider
                
                DispatchQueue.main.async {
                    if type == .local, let localURL = self.vaultURL {
                        self.setupVaultMonitor(for: localURL)
                    } else {
                        self.vaultMonitor?.stop()
                        self.vaultMonitor = nil
                    }
                    
                    NSFileCoordinator.addFilePresenter(self)
                    self.isRunning = true
                    self.status = .active
                    self.log("👀 Watcher Active (\(type == .s3 ? "Cloud Mode" : "Local Mode"))")
                    
                    self.cleanupStaleUploads()
                    self.performInitialScan()
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.log("❌ Failed to create Vault connection: \(error.localizedDescription)")
                    self.status = .disabled
                }
            }
        }
    }
    
    private func setupVaultMonitor(for url: URL) {
        vaultMonitor?.stop()
        
        vaultMonitor = VaultMonitor(url: url)
        
        vaultMonitor?.onDisconnect = { [weak self] in
            self?.suspendForDisconnection()
        }
        
        vaultMonitor?.onReconnect = { [weak self] in
            self?.resumeFromDisconnection()
        }
        
        vaultMonitor?.start()
    }
    
    private func suspendForDisconnection() {
        guard isRunning else { return }
        
        log("⚠️ Vault disconnected! Pausing watcher...")
        
        NSFileCoordinator.removeFilePresenter(self)
        
        self.vaultURL?.stopAccessingSecurityScopedResource()
        self.sourceURL?.stopAccessingSecurityScopedResource()
        
        self.status = .waitingForVault
        
        NotificationManager.shared.send(
            title: "Drive Paused",
            body: "The Vault drive was disconnected. Anchor will resume when it returns.",
            type: .vaultIssue
        )
    }
    
    private func resumeFromDisconnection() {
        guard status == .waitingForVault else { return }
        
        log("✅ Vault reconnected. Resuming...")
        
        guard let newSource = PersistenceManager.shared.loadBookmark(type: .driveSource),
              let newVault = PersistenceManager.shared.loadBookmark(type: .driveVault) else {
            log("❌ Critical: Could not restore bookmarks after reconnect.")
            self.status = .disabled
            return
        }
        
        guard newSource.startAccessingSecurityScopedResource(),
              newVault.startAccessingSecurityScopedResource() else {
            log("❌ Critical: Permission denied on reconnected drive.")
            self.status = .disabled
            return
        }
        
        self.sourceURL = newSource
        self.vaultURL = newVault
        
        NSFileCoordinator.addFilePresenter(self)
        self.status = .monitoring
        
        performInitialScan()
    }
    
    
    func performInitialScan() {
        guard NetworkMonitor.shared.status == .verified else {
            log("⏳ Waiting for Internet to start Smart Scan...")
            self.status = .paused
            return
        }
        if PersistenceManager.shared.isGlobalPaused { self.status = .paused; return }
        guard PersistenceManager.shared.isDriveEnabled else { return }
        guard let source = sourceURL else { return }
        
        DispatchQueue.main.async {
            self.isScanning = true
            self.status = .scanning
            self.sessionScannedCount = 0
        }
        log("🔎 Starting Smart Scan (Checking Generation IDs)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Anchor Smart Scan"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            
            if PersistenceManager.shared.isGlobalPaused {
                DispatchQueue.main.async { self.status = .paused }
                return
            }
            guard PersistenceManager.shared.isDriveEnabled else { return }
            
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [
                .ubiquitousItemDownloadingStatusKey,
                .generationIdentifierKey,
                .isDirectoryKey,
                .isPackageKey
            ]
            
            guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
            
            var processed = 0
            var skipped = 0
            
            for case let fileURL as URL in enumerator {
                if PersistenceManager.shared.isGlobalPaused {
                    DispatchQueue.main.async { self.status = .paused }
                    break
                }
                if !PersistenceManager.shared.isDriveEnabled { break }
                if (processed + skipped) % 50 == 0 {
                    DispatchQueue.main.async {
                        self.sessionScannedCount = processed + skipped
                    }
                }
                
                if ExclusionManager.shared.shouldIgnore(url: fileURL) {
                    if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let isPackage = resourceValues?.isPackage ?? false
                
                if isDirectory {
                    if isPackage {
                        // It's a Bundle (e.g. .app, .numbers).
                        enumerator.skipDescendants()
                    } else {
                        continue
                    }
                }
                
                guard let metadata = self.extractMetadata(for: fileURL) else { continue }
                
                if self.ledger.shouldProcess(relativePath: metadata.relativePath, currentGenID: metadata.genID) {
                    self.processFile(at: fileURL, genID: metadata.genID, relativePath: metadata.relativePath)
                    processed += 1
                } else {
                    skipped += 1
                }
            }
            
            DispatchQueue.main.async {
                self.isScanning = false
                self.sessionScannedCount = processed + skipped
                
                if PersistenceManager.shared.isDriveEnabled {
                    self.status = .monitoring
                    self.log("✅ Smart Scan Complete. Processed: \(processed), Skipped: \(skipped)")
                    if processed > 0 {
                        NotificationManager.shared.send(
                            title: "Drive Scan Complete",
                            body: "Processed \(processed) files. Anchor is now monitoring for changes.",
                            type: .backupComplete
                        )
                    }
                } else {
                    self.status = .disabled
                    self.log("🚫 Scan aborted (Disabled).")
                }
            }
        }
    }
    
    private func extractMetadata(for url: URL) -> (genID: String, relativePath: String)? {
        guard let source = sourceURL else { return nil }
        
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .generationIdentifierKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        
       if values.isDirectory == true {
            let isPackage = values.isPackage ?? false
            if !isPackage {
                return nil
            }
        }
        
        let filePath = url.standardized.path
        let sourcePath = source.standardized.path
        
        if !filePath.hasPrefix(sourcePath) { return nil }
        
        var relativePath = String(filePath.dropFirst(sourcePath.count))
        while relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        
        guard let rawID = values.generationIdentifier else {
            return ("unknown_\(Date().timeIntervalSince1970)", relativePath)
        }
        
        let genID = String(describing: rawID)
        return (genID, relativePath)
    }
    
    private func processFile(at url: URL, genID: String, relativePath: String) {
        guard NetworkMonitor.shared.status == .verified else {
            log("⏳ Queued \(url.lastPathComponent) (Waiting for Internet)")
            return
        }
        DispatchQueue.main.async {
            self.lastFileProcessed = url.lastPathComponent
        }
        
        if let storedPath = ledger.getStoredCasing(for: relativePath) {
            if storedPath != relativePath {
                log("🔠 Case change detected: \(storedPath) -> \(relativePath)")
                Task {
                    try? await vaultProvider?.deleteFile(relativePath: storedPath)
                }
            }
        }
        
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            let status = values.ubiquitousItemDownloadingStatus
            
            if status == .current {
                copyToVault(fileURL: url, relativePath: relativePath, genID: genID)
            } else if status == .notDownloaded {
                DispatchQueue.main.async { self.status = .downloading(filename: url.lastPathComponent) }
                log("☁️ Downloading update: \(url.lastPathComponent)")
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } else {
                copyToVault(fileURL: url, relativePath: relativePath, genID: genID)
            }
        } catch {
            log("⚠️ Error processing \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    private func copyToVault(fileURL: URL, relativePath: String, genID: String) {
        guard let provider = vaultProvider else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            
            coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordError) { safeURL in
                
                let fileSize = (try? safeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                
                if fileSize == 0 {
                    self.log("⚠️ Zero-byte file detected after lock release: \(safeURL.lastPathComponent). Skipping.")
                    return
                }
                
                Task {
                    await performWithActivity("Uploading \(fileURL)"){
                        do {
                            try await provider.saveFile(source: fileURL, relativePath: relativePath)
                            
                            await self.ledger.markAsProcessed(relativePath: relativePath, genID: genID)
                            
                            await MainActor.run {
                                self.sessionVaultedCount += 1
                                self.lastSyncTime = Date()
                                self.status = .vaulted(filename: fileURL.lastPathComponent)
                            }
                        }catch let error as VaultError {
                            if case .diskFull(let required, _) = error {
                                let sizeStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
                                
                                await MainActor.run{
                                    self.log("⛔️ Backup Failed: Disk Full. Needed \(sizeStr).")
                                    self.status = .disabled
                                }
                                
                                DispatchQueue.main.async {
                                    NotificationManager.shared.send(
                                        title: "Backup Failed: Disk Full",
                                        body: "Anchor requires \(sizeStr) to back up '\(safeURL.lastPathComponent)'. Sync has been paused.",
                                        type: .vaultIssue
                                    )
                                }
                            }
                        } catch {
                            await self.log("⚠️ Upload/Copy Failed: \(error.localizedDescription)")
                            
                            if (error as NSError).domain == NSCocoaErrorDomain {
                                await NotificationManager.shared.send(
                                    title: "Vault Error",
                                    body: "Failed to save file. Check your connection.",
                                    type: .vaultIssue
                                )
                            }
                        }
                    }
                }
            }
            
            if let error = coordError {
                self.log("🔒 Locked File Skipped: \(error.localizedDescription)")
            }
        }
    }
    
    private func requestFolderAccess(prompt: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow Access"
        panel.message = prompt
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                completion(url)
            }
        }
    }
    
    private func log(_ message: String) {
        print(message)
        DispatchQueue.main.async {
            if self.logs.count > 100 { self.logs.removeFirst() }
            self.logs.append(LogEntry(message: message))
        }
    }
}
