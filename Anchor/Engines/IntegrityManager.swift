//
//  IntegrityManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 11/02/2026.
//
import Foundation
import SwiftUI
import Combine

class IntegrityManager: ObservableObject {
    static let shared = IntegrityManager()
    
    @Published var filesVerified: Int = 0
    @Published var filesPending: Int = 0
    @Published var filesWithErrors: Int = 0
    @Published var totalFiles: Int = 0
    @Published var isVerifying: Bool = false
    
    private let ledger = SQLiteLedger.shared
    private let queue = DispatchQueue(label: "com.anchor.integrity", qos: .utility)
    private var isRunning = false
    private var verificationTask: Task<Void, Never>?
    
    private init() {
        updateStats()
    }
    
    func updateStats() {
        let stats = ledger.getVerificationStats()
        
        Task { @MainActor in
            self.filesVerified = stats.verified
            self.filesPending = stats.pending
            self.filesWithErrors = stats.errors
            self.totalFiles = stats.total
        }
    }
    
    func startVerification() {
        if PersistenceManager.shared.isGlobalPaused {
            print("IntegrityManager: Global pause active. Skipping.")
            return
        }
        
        guard !isRunning else { return }
        
        isRunning = true
        
        print("IntegrityManager: Starting background verification")
        
        verificationTask = Task.detached(priority: .utility) { [weak self] in
            await self?.verificationLoop()
        }
    }
    
    func stopVerification() {
        isRunning = false
        verificationTask?.cancel()
        verificationTask = nil
        
        Task { @MainActor in
            self.isVerifying = false
        }
        
        print("IntegrityManager: Stopped verification")
    }
    
    func verifyNow() {
        Task {
            await performVerificationCycle()
        }
    }
    
    private func verificationLoop() async {
        while isRunning {
            await performVerificationCycle()
            
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                print("IntegrityManager: Sleep interrupted")
            }
        }
    }
    
    private func performVerificationCycle() async {
        await MainActor.run {
            self.isVerifying = true
        }
        
        defer {
            Task { @MainActor in
                self.isVerifying = false
            }
        }
        
        let driveVaultType = PersistenceManager.shared.driveVaultType
        let photoVaultType = PersistenceManager.shared.photoVaultType
        let networkStatus = NetworkMonitor.shared.status
        
        if (driveVaultType == .s3 || photoVaultType == .s3) && networkStatus != .verified {
            print("IntegrityManager: Network offline, skipping verification cycle")
            return
        }
        
        let driveProvider = try? await VaultFactory.getProvider(type: driveVaultType, bookmarkType: .driveVault)
        let photoProvider = try? await VaultFactory.getProvider(type: photoVaultType, bookmarkType: .photoVault)
        
        if driveProvider == nil && photoProvider == nil {
            print("IntegrityManager: No vaults available, skipping verification cycle")
            return
        }
        
        let filesToVerify = ledger.getFilesForAuditing(limit: 50)
        
        if filesToVerify.isEmpty {
            print("IntegrityManager: No files need verification")
            await MainActor.run {
                self.updateStats()
            }
            return
        }
        
        print("IntegrityManager: Verifying \(filesToVerify.count) files")
        
        for (path, expectedHash) in filesToVerify {
            let provider: VaultProvider?
            if path.hasPrefix("drive/") {
                provider = driveProvider
            } else if path.hasPrefix("photos/") {
                provider = photoProvider
            } else {
                provider = driveProvider
            }
            
            guard let vaultProvider = provider else {
                print("IntegrityManager: No provider for \(path)")
                continue
            }
            
            _ = await verifyFile(path: path, expectedHash: expectedHash, provider: vaultProvider)
            
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        await MainActor.run {
            self.updateStats()
        }
    }
    
    private func verifyFile(path: String, expectedHash: String, provider: VaultProvider) async -> Bool {
        do {
            let metadata = try await provider.getMetadata(for: path)
            
            guard let remoteHash = metadata["original-sha256"] else {
                print("IntegrityManager: ⚠️ Metadata missing for \(path)")
                
                if provider is LocalVault {
                    print("IntegrityManager: 🔧 Attempting self-heal for local file \(path)")
                    
                    do {
                        let vaultURL: URL?
                        if path.hasPrefix("drive/") {
                            vaultURL = PersistenceManager.shared.loadBookmark(type: .driveVault)
                        } else if path.hasPrefix("photos/") {
                            vaultURL = PersistenceManager.shared.loadBookmark(type: .photoVault)
                        } else {
                            vaultURL = PersistenceManager.shared.loadBookmark(type: .driveVault)
                        }
                        
                        guard let vault = vaultURL else {
                            print("IntegrityManager: Cannot self-heal - vault URL not available")
                            return false
                        }
                        
                        let fileURL = vault.appendingPathComponent(path)
                        let calculatedHash = try CryptoManager.shared.calculateSHA256(for: fileURL)
                        
                        if calculatedHash == expectedHash {
                            print("IntegrityManager: ✅ Self-heal successful - file is intact, writing metadata")
                            
                            let xattrKey = "com.anchor.original-sha256"
                            setxattr(fileURL.path, xattrKey, calculatedHash, calculatedHash.utf8.count, 0, 0)
                            
                            ledger.updateVerificationStatus(path: path, status: 1, date: Date())
                            return true
                        } else {
                            print("IntegrityManager: ❌ Self-heal failed - hash mismatch")
                            print("  Expected: \(expectedHash)")
                            print("  Actual:   \(calculatedHash)")
                            ledger.updateVerificationStatus(path: path, status: 2, date: Date())
                            return false
                        }
                    } catch {
                        print("IntegrityManager: Self-heal error: \(error)")
                        ledger.updateVerificationStatus(path: path, status: 3, date: Date())
                        return false
                    }
                } else {
                    ledger.updateVerificationStatus(path: path, status: 3, date: Date())
                    return false
                }
            }
            
            if remoteHash == expectedHash {
                print("IntegrityManager: ✅ Verified \(path)")
                ledger.updateVerificationStatus(path: path, status: 1, date: Date())
                return true
            } else {
                print("IntegrityManager: MISMATCH detected for \(path)")
                print("  Expected: \(expectedHash)")
                print("  Remote:   \(remoteHash)")
                ledger.updateVerificationStatus(path: path, status: 2, date: Date())
                
                NotificationManager.shared.send(
                    title: "Integrity Mismatch Detected",
                    body: "File '\(path)' has a hash mismatch. Backup may be corrupted.",
                    type: .vaultIssue
                )
                
                Task { @MainActor in
                    WebhookManager.shared.send(
                        event: .integrityMismatch,
                        errorMessage: "File '\(path)' has a hash mismatch. Expected: \(expectedHash), Remote: \(remoteHash)"
                    )
                }
                
                return false
            }
            
        } catch {
            print("IntegrityManager: Error verifying \(path): \(error)")
            ledger.updateVerificationStatus(path: path, status: 3, date: Date())
            
            Task { @MainActor in
                WebhookManager.shared.send(
                    event: .integrityError,
                    errorMessage: "Error verifying '\(path)': \(error.localizedDescription)"
                )
            }
            
            return false
        }
    }
    
    func verifySingleFile(path: String, provider: VaultProvider) async -> Bool {
        guard let hash = ledger.getContentHash(for: path) else { return false }
        return await verifyFile(path: path, expectedHash: hash, provider: provider)
    }
}
