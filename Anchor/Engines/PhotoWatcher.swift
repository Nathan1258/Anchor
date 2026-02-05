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
    
    // MARK: - Configuration
    @Published var vaultURL: URL?
    @Published var isRunning = false
    
    // MARK: - UI / Dashboard State
    @Published var statusMessage = "Waiting to start..."
    @Published var isProcessing = false
    @Published var lastSyncTime: Date? = nil
    
    // MARK: - Metrics
    @Published var totalLibraryCount: Int = 0
    @Published var sessionSavedCount: Int = 0
    @Published var lastPhotoProcessed: String = "-"
    
    // MARK: - Debug
    @Published var logs: [String] = []
    
    private let exportQueue = DispatchQueue(label: "com.anchor.photoExport", qos: .utility)
    
    override init() {
        super.init()
        restoreState()
    }
    
    private func restoreState() {
        if let source = PersistenceManager.shared.loadBookmark(type: .photoVault) {
            if source.startAccessingSecurityScopedResource() {
                self.vaultURL = source
            }
        }
        
        if vaultURL != nil {
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
                PersistenceManager.shared.saveBookmark(for: url, type: .photoVault)
                self.log("📸 Photo Vault set to: \(url.path)")
            }
        }
    }
    
    func startWatching() {
        guard vaultURL != nil else {
            log("⚠️ Select a Vault folder first.")
            return
        }
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    self.registerObserver()
                    self.checkForChanges()
                } else {
                    self.log("❌ Photos Access Denied.")
                    self.statusMessage = "Access Denied"
                }
            }
        }
    }
    
    private func registerObserver() {
        PHPhotoLibrary.shared().register(self)
        self.isRunning = true
        self.statusMessage = "Monitoring Library"
        self.log("👀 Watching Photo Library for changes...")
    }
    
    private func checkForChanges() {
        guard let lastToken = PersistenceManager.shared.loadPhotoToken() else {
            performFullScan()
            return
        }
        
        // UI
        DispatchQueue.main.async {
            self.isProcessing = true
            self.statusMessage = "Checking for new photos..."
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
    
    // 1. Add ability to sync fully or only sync new changes (or potentially sync from a certain date onwards)
    // 2. Add toggle to sync changes or not
    private func processDelta(_ changes: PHPersistentChangeFetchResult) {
        exportQueue.async {
            var addedCount = 0
            var updatedCount = 0
            
            for change in changes {
                do{
                    let details = try change.changeDetails(for: .asset)
                    let inserted = details.insertedLocalIdentifiers
                    if !inserted.isEmpty {
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(inserted), options: nil)
                        assets.enumerateObjects { asset, _, _ in
                            autoreleasepool {
                                self.exportAsset(asset, forceOverwrite: false)
                                addedCount += 1
                            }
                        }
                    }
                    
                    // 2. Handle EDITED items (Updates)
                    //                let updated = details.updatedLocalIdentifiers
                    //                if !updated.isEmpty {
                    //                    let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(updated), options: nil)
                    //                    assets.enumerateObjects { asset, _, _ in
                    //                        autoreleasepool {
                    //                            // Force overwrite because the photo has changed
                    //                            self.exportAsset(asset, forceOverwrite: true)
                    //                            updatedCount += 1
                    //                        }
                    //                    }
                    //                }
                    
                    PersistenceManager.shared.savePhotoToken(change.changeToken)
                    
                }catch{
                    self.logs.append("⚠️ Error processing change: \(error)")
                    continue
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                if addedCount > 0 || updatedCount > 0 {
                    self.statusMessage = "Synced \(addedCount) new items"
                    self.log("⚡️ Delta Sync: \(addedCount) added, \(updatedCount) updated.")
                } else {
                    self.statusMessage = "Up to date"
                    self.log("✅ Smart Scan: No relevant changes found.")
                }
            }
        }
    }
    
    private func performFullScan() {
        DispatchQueue.main.async {
            self.statusMessage = "Scanning entire library..."
            self.isProcessing = true
        }
        log("🐢 First Run: Scanning entire library...")
        
        exportQueue.async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let allAssets = PHAsset.fetchAssets(with: options)
            
            DispatchQueue.main.async {
                self.totalLibraryCount = allAssets.count
                self.log("Found \(allAssets.count) items. Starting Backup...")
            }
            
            allAssets.enumerateObjects { (asset, index, stop) in
                if index % 10 == 0 {
                    DispatchQueue.main.async {
                        self.statusMessage = "Processing \(index)/\(allAssets.count)..."
                    }
                }
                self.exportAsset(asset)
            }
            
            let currentToken = PHPhotoLibrary.shared().currentChangeToken
            PersistenceManager.shared.savePhotoToken(currentToken)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.statusMessage = "Full Backup Complete"
                self.log("✅ Full Scan Complete. Token Saved.")
            }
        }
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            self.checkForChanges()
        }
    }
    
    private func exportAsset(_ asset: PHAsset, forceOverwrite: Bool = false) {
        guard let vault = vaultURL else { return }
        
        DispatchQueue.main.async {
            self.lastPhotoProcessed = "Item..."
        }
        
        let date = asset.creationDate ?? Date()
        let calendar = Calendar.current
        let year = String(calendar.component(.year, from: date))
        let month = String(format: "%02d", calendar.component(.month, from: date))
        
        let folderURL = vault.appendingPathComponent(year).appendingPathComponent(month)
        
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch { return }
        
        let resources = PHAssetResource.assetResources(for: asset)
        guard let mainResource = resources.first(where: { $0.type == .photo || $0.type == .video }) else { return }
        
        let filename = mainResource.originalFilename
        let destinationURL = folderURL.appendingPathComponent(filename)
        
        DispatchQueue.main.async { self.lastPhotoProcessed = filename }
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if forceOverwrite {
                try? FileManager.default.removeItem(at: destinationURL)
            } else {
                return
            }
        }
        
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        
        PHAssetResourceManager.default().writeData(for: mainResource, toFile: destinationURL, options: options) { error in
            if let e = error {
                self.log("⚠️ Failed: \(filename) - \(e.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    self.sessionSavedCount += 1
                    self.lastSyncTime = Date()
                }
                self.log(forceOverwrite ? "♻️ Updated: \(filename)" : "✅ Saved: \(filename)")
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
