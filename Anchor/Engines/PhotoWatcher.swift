//
//  PhotoWatcher.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import Photos
import SwiftUI
import Combine

class PhotoWatcher: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var vaultURL: URL?
    @Published var isRunning = false
    
    @Published var status: PhotosStatus = .waiting
    @Published var isProcessing = false
    @Published var lastSyncTime: Date? = nil
    
    @Published var totalLibraryCount: Int = 0
    @Published var sessionSavedCount: Int = 0
    @Published var lastPhotoProcessed: String = "-"
    
    @Published var logs: [String] = []
    
    private var vaultProvider: VaultProvider?
    private var vaultMonitor: VaultMonitor?
    
    private let exportQueue = DispatchQueue(label: "com.anchor.photoExport", qos: .utility)
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
        if PersistenceManager.shared.photoVaultType == .local,
           let source = PersistenceManager.shared.loadBookmark(type: .photoVault) {
            if source.startAccessingSecurityScopedResource() {
                self.vaultURL = source
            }
        }
        
        let isLocalReady = (PersistenceManager.shared.photoVaultType == .local && vaultURL != nil)
        let isS3Ready = (PersistenceManager.shared.photoVaultType == .s3 && PersistenceManager.shared.s3Config.isValid)
        
        if isLocalReady || isS3Ready {
            log("♻️ Restored previous session. Auto-starting...")
            startWatching()
        }
    }
    
    func selectVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select Photo Vault"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.vaultURL = url
                PersistenceManager.shared.photoVaultType = .local
                PersistenceManager.shared.saveBookmark(for: url, type: .photoVault)
                self.log("📸 Photo Vault set to: \(url.path)")
            }
        }
    }
    
    func startWatching() {
        guard !PersistenceManager.shared.isGlobalPaused else {
            log("Global Pause Active. Watcher standing by.")
            self.status = .paused
            return
        }
        
        guard PersistenceManager.shared.isPhotosEnabled else {
            log("🚫 Photo Backup is disabled in Settings.")
            self.status = .disabled
            return
        }
        
        if PersistenceManager.shared.photoVaultType == .local && vaultURL == nil {
            log("⚠️ Select a Vault folder first.")
            return
        }
        
        self.status = .waitingForVault
        
        Task {
            let type = PersistenceManager.shared.photoVaultType
            
            do {
                guard let provider = try await VaultFactory.getProvider(type: type) else {
                    DispatchQueue.main.async {
                        self.log("❌ Error: Could not initialize Photo Vault Provider.")
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
                    
                    self.requestPhotoAccess()
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.log("❌ Connection Error: \(error.localizedDescription)")
                    self.status = .disabled
                }
            }
        }
    }
    
    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    self.registerObserver()
                    if self.status != .waitingForVault {
                        self.checkForChanges()
                    }
                } else {
                    self.log("❌ Photos Access Denied.")
                    self.status = .accessDenied
                }
            }
        }
    }
    
    private func setupVaultMonitor(for url: URL) {
        vaultMonitor?.stop()
        vaultMonitor = VaultMonitor(url: url)
        
        vaultMonitor?.onDisconnect = { [weak self] in
            self?.log("⚠️ Photo Vault disconnected! Pausing export.")
            
            self?.vaultURL?.stopAccessingSecurityScopedResource()
            
            self?.status = .waitingForVault
            
            NotificationManager.shared.send(
                title: "Photo Backup Paused",
                body: "The Photo Vault drive was disconnected.",
                type: .vaultIssue
            )
        }
        
        vaultMonitor?.onReconnect = { [weak self] in
            self?.log("✅ Photo Vault reconnected. Resuming...")
            guard let newVault = PersistenceManager.shared.loadBookmark(type: .photoVault) else {
                self?.log("❌ Failed to resolve bookmark.")
                return
            }
            
            if newVault.startAccessingSecurityScopedResource() {
                self?.vaultURL = newVault
                self?.status = .monitoring
                self?.log("✅ Resumed.")
                self?.checkForChanges()
            } else {
                self?.log("❌ Permission denied on reconnect.")
                self?.status = .accessDenied
                
            }
        }
        
        vaultMonitor?.start()
    }
    
    private func registerObserver() {
        PHPhotoLibrary.shared().register(self)
        self.isRunning = true
        self.status = .monitoring
        self.log("👀 Watching Photo Library for changes...")
    }
    
    private func checkForChanges() {
        if PersistenceManager.shared.isGlobalPaused {
            DispatchQueue.main.async { self.status = .paused }
            return
        }
        guard PersistenceManager.shared.isPhotosEnabled else { return }
        
        guard let lastToken = PersistenceManager.shared.loadPhotoToken() else {
            performFullScan()
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.status = .checkingForChanges
        }
        
        log("🔎 Checking for new photos since last run...")
        
        do {
            let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: lastToken)
            processDelta(changes)
        } catch {
            log("⚠️ Error checking changes: \(error). Falling back to full scan.")
            performFullScan()
        }
    }
    
    private func processDelta(_ changes: PHPersistentChangeFetchResult) {
        exportQueue.async {
            let shouldContinue = DispatchQueue.main.sync {
                if PersistenceManager.shared.isGlobalPaused {
                    self.status = .paused
                    return false
                }
                return self.status != .waitingForVault && PersistenceManager.shared.isPhotosEnabled
            }
            
            guard shouldContinue else { return }
            
            var addedCount = 0
            let updatedCount = 0
            
            for change in changes {
                if PersistenceManager.shared.isGlobalPaused {
                    DispatchQueue.main.async { self.status = .paused }
                    break
                }
                
                guard shouldContinue else { return }
                do{
                    let details = try change.changeDetails(for: .asset)
                    let inserted = details.insertedLocalIdentifiers
                    if !inserted.isEmpty {
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(inserted), options: nil)
                        assets.enumerateObjects { asset, _, stop in
                            if !PersistenceManager.shared.isPhotosEnabled {
                                stop.pointee = true
                                return
                            }
                            
                            autoreleasepool {
                                self.exportAsset(asset, forceOverwrite: false)
                                addedCount += 1
                            }
                        }
                    }
                    if PersistenceManager.shared.isPhotosEnabled {
                        PersistenceManager.shared.savePhotoToken(change.changeToken)
                    }
                    
                }catch{
                    self.logs.append("⚠️ Error processing change: \(error)")
                    continue
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                if PersistenceManager.shared.isPhotosEnabled {
                    if addedCount > 0 || updatedCount > 0 {
                        self.status = .synced(count: addedCount)
                        self.log("⚡️ Delta Sync: \(addedCount) added, \(updatedCount) updated.")
                        NotificationManager.shared.send(
                            title: "Photos Synced",
                            body: "Saved \(addedCount) new photos to Vault.",
                            type: .backupComplete
                        )
                    } else {
                        self.status = .upToDate
                        self.log("✅ Smart Scan: No relevant changes found.")
                    }
                } else {
                    self.status = .disabled
                }
            }
        }
    }
    
    private func performFullScan() {
        guard self.status != .waitingForVault,
              PersistenceManager.shared.isPhotosEnabled else { return }
        
        DispatchQueue.main.async {
            self.status = .scanning
            self.isProcessing = true
        }
        log("🐢 First Run: Scanning entire library...")
        
        exportQueue.async {
            guard PersistenceManager.shared.isPhotosEnabled else { return }
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let allAssets = PHAsset.fetchAssets(with: options)
            
            DispatchQueue.main.async {
                self.totalLibraryCount = allAssets.count
                self.log("Found \(allAssets.count) items. Starting Backup...")
            }
            
            allAssets.enumerateObjects { (asset, index, stop) in
                let shouldStop = DispatchQueue.main.sync {
                    self.status == .waitingForVault || !PersistenceManager.shared.isPhotosEnabled
                }
                
                if shouldStop {
                    stop.pointee = true
                    return
                }
                
                if index % 10 == 0 {
                    DispatchQueue.main.async {
                        self.status = .processing(current: index, total: allAssets.count)
                    }
                }
                self.exportAsset(asset)
            }
            
            let currentToken = PHPhotoLibrary.shared().currentChangeToken
            PersistenceManager.shared.savePhotoToken(currentToken)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.status = .backupComplete
                self.log("✅ Full Scan Complete. Token Saved.")
                
                NotificationManager.shared.send(
                    title: "Photo Backup Complete",
                    body: "Your entire library has been scanned and backed up.",
                    type: .backupComplete
                )
            }
        }
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard PersistenceManager.shared.isPhotosEnabled else { return }
        
        DispatchQueue.main.async {
            self.checkForChanges()
        }
    }
    
    private func exportAsset(_ asset: PHAsset, forceOverwrite: Bool = false) {
        guard let provider = vaultProvider else { return }
        
        DispatchQueue.main.async { self.lastPhotoProcessed = "Processing..." }
        
        let date = asset.creationDate ?? Date()
        let calendar = Calendar.current
        let year = String(calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        
        let resources = PHAssetResource.assetResources(for: asset)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let group = DispatchGroup()
        
        actor ResultsCollector {
            var errors: [String] = []
            var savedFilenames: [String] = []
            
            func addError(_ error: String) {
                errors.append(error)
            }
            
            func addSavedFile(_ filename: String) {
                savedFilenames.append(filename)
            }
            
            func getResults() -> (errors: [String], savedFilenames: [String]) {
                return (errors, savedFilenames)
            }
        }
        
        let collector = ResultsCollector()
        
        for resource in resources {
            group.enter()
            
            let filename = resource.originalFilename
            let relativePath = "\(year)/\(month)/\(filename)"
            let tempFileURL = tempDir.appendingPathComponent(filename)
            
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            
            PHAssetResourceManager.default().writeData(for: resource, toFile: tempFileURL, options: options) { error in
                if let error {
                    Task { @MainActor in
                        self.log("⚠️ Failed: \(filename) - \(error.localizedDescription)")
                    }
                    
                    if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == 4 {
                        NotificationManager.shared.send(
                            title: "Vault Disconnected",
                            body: "Could not write to Photo Vault. Please check your drive connection.",
                            type: .vaultIssue
                        )
                    }
                    group.leave()
                    return
                }
                
                Task {
                    do {
                        let exists = await provider.fileExists(relativePath: relativePath)
                        
                        if !exists {
                            try await provider.saveFile(source: tempFileURL, relativePath: relativePath)
                            await collector.addSavedFile(filename)
                        }
                        
                        try? FileManager.default.removeItem(at: tempFileURL)
                        
                    } catch {
                        await Task { @MainActor in
                            self.log("⚠️ Upload Failed: \(filename) - \(error.localizedDescription)")
                        }.value
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            try? FileManager.default.removeItem(at: tempDir)
            
            Task { @MainActor in
                let results = await collector.getResults()
                
                if !results.savedFilenames.isEmpty {
                    self.sessionSavedCount += 1
                    self.lastSyncTime = Date()
                    
                    if let primeFile = results.savedFilenames.first {
                        self.lastPhotoProcessed = primeFile
                        self.log(forceOverwrite ? "♻️ Updated: \(primeFile)" : "✅ Saved: \(primeFile) (+ components)")
                    }
                }
                
                if !results.errors.isEmpty {
                    self.log("⚠️ Issues saving asset components: \(results.errors.joined(separator: ", "))")
                }
            }
        }
    }
    
    private func log(_ message: String) {
        print(message)
        DispatchQueue.main.async {
            self.logs.append(message)
        }
    }
}
