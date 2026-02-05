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
    
    private var vaultMonitor: VaultMonitor?
    
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        restoreState()
        setupPauseObserver()
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
    
    private func restoreState() {
        if let source = PersistenceManager.shared.loadBookmark(type: .driveSource) {
            if source.startAccessingSecurityScopedResource() {
                self.sourceURL = source
            }
        }
        
        if let vault = PersistenceManager.shared.loadBookmark(type: .driveVault) {
            if vault.startAccessingSecurityScopedResource() {
                self.vaultURL = vault
            }
        }
        
        if sourceURL != nil && vaultURL != nil {
            log("♻️ Restored previous session. Auto-starting...")
            startWatching()
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
        handleIncomingFile(at: url)
    }
    
    func presentedSubitemDidChange(at url: URL) {
        if PersistenceManager.shared.isGlobalPaused {
            DispatchQueue.main.async { self.status = .paused }
            return
        }
        guard PersistenceManager.shared.isDriveEnabled else { return }
        
        DispatchQueue.main.async { self.status = .changeDetected }
        log("Hz Change Detected: \(url.lastPathComponent)")
        handleIncomingFile(at: url)
    }
    
    private func getRelativePath(for url: URL) -> String? {
        guard let source = sourceURL else { return nil }
        let filePath = url.path
        let sourcePath = source.path
        if !filePath.hasPrefix(sourcePath) { return nil }
        return String(filePath.dropFirst(sourcePath.count))
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
    
    private func deleteFromVault(relativePath: String) {
        guard let vault = vaultURL else { return }
        let destURL = URL(fileURLWithPath: vault.path + relativePath)
        
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
                ledger.removeEntry(relativePath: relativePath)
                log("🗑️ Synced Deletion: \(relativePath)")
                
                DispatchQueue.main.async {
                    self.status = .deleted(filename: destURL.lastPathComponent)
                }
            }
        } catch {
            log("⚠️ Failed to delete vault copy: \(error.localizedDescription)")
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
        
        guard let source = sourceURL, let vault = vaultURL else {
            log("❌ Error: Select both folders first.")
            return
        }
        
        if !source.startAccessingSecurityScopedResource() {
            log("❌ Failed to access source folder. Check Permissions.")
            return
        }
        
        setupVaultMonitor(for: vault)
        
        if !source.startAccessingSecurityScopedResource() {
            log("❌ Failed to access source folder. Check Permissions.")
            return
        }
        
        NSFileCoordinator.addFilePresenter(self)
        self.isRunning = true
        self.status = .active
        log("👀 Watcher Registered via NSFilePresenter")
        
        performInitialScan()
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
            
            if PersistenceManager.shared.isGlobalPaused {
                DispatchQueue.main.async { self.status = .paused }
                return
            }
            guard PersistenceManager.shared.isDriveEnabled else { return }
            
            let fileManager = FileManager.default
            let keys: [URLResourceKey] = [
                .ubiquitousItemDownloadingStatusKey,
                .generationIdentifierKey,
                .isDirectoryKey
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
        
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
            return nil
        }
        
        let filePath = url.path
        let sourcePath = source.path
        if !filePath.hasPrefix(sourcePath) { return nil }
        let relativePath = String(filePath.dropFirst(sourcePath.count))
        
        let keys: Set<URLResourceKey> = [.generationIdentifierKey]
        
        guard let values = try? url.resourceValues(forKeys: keys),
              let rawID = values.generationIdentifier else {
            return ("unknown_\(Date().timeIntervalSince1970)", relativePath)
        }
        
        let genID = String(describing: rawID)
        return (genID, relativePath)
    }
    
    private func processFile(at url: URL, genID: String, relativePath: String) {
        DispatchQueue.main.async {
            self.lastFileProcessed = url.lastPathComponent
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
        guard let vault = vaultURL else { return }
        
        let destinationPath = vault.path + relativePath
        let destURL = URL(fileURLWithPath: destinationPath)
        
        do {
            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(at: destURL)
            }
            
            try FileManager.default.copyItem(at: fileURL, to: destURL)
            
            ledger.markAsProcessed(relativePath: relativePath, genID: genID)
            
            DispatchQueue.main.async {
                self.sessionVaultedCount += 1
                self.lastSyncTime = Date()
                self.status = .vaulted(filename: fileURL.lastPathComponent)
            }
            log("✅ Vaulted: \(fileURL.lastPathComponent)")
            
        } catch {
            log("⚠️ Copy Failed: \(error.localizedDescription)")
            
            if (error as NSError).domain == NSCocoaErrorDomain {
                NotificationManager.shared.send(
                    title: "Drive Vault Error",
                    body: "Failed to copy file. Check if your Vault drive is connected.",
                    type: .vaultIssue
                )
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
