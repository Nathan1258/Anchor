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
    
    /// Updates the published statistics
    func updateStats() {
        let stats = ledger.getVerificationStats()
        
        Task { @MainActor in
            self.filesVerified = stats.verified
            self.filesPending = stats.pending
            self.filesWithErrors = stats.errors
            self.totalFiles = stats.total
        }
    }
    
    /// Starts the background integrity verification process
    func startVerification() {
        guard !isRunning else { return }
        
        isRunning = true
        
        Task { @MainActor in
            self.isVerifying = true
        }
        
        print("IntegrityManager: Starting background verification")
        
        verificationTask = Task.detached(priority: .utility) { [weak self] in
            await self?.verificationLoop()
        }
    }
    
    /// Stops the background integrity verification process
    func stopVerification() {
        isRunning = false
        verificationTask?.cancel()
        verificationTask = nil
        
        Task { @MainActor in
            self.isVerifying = false
        }
        
        print("IntegrityManager: Stopped verification")
    }
    
    /// Main verification loop that runs continuously
    private func verificationLoop() async {
        while isRunning {
            do {
                // Get vault providers
                guard let driveProvider = try await VaultFactory.getProvider(type: PersistenceManager.shared.driveVaultType, bookmarkType: .driveVault) else {
                    print("IntegrityManager: Drive vault not available, waiting...")
                    try await Task.sleep(for: .seconds(300)) // Wait 5 minutes
                    continue
                }
                
                let photoProvider = try? await VaultFactory.getProvider(type: PersistenceManager.shared.photoVaultType, bookmarkType: .photoVault)
                
                // Get batch of files to verify
                let filesToVerify = ledger.getFilesForAuditing(limit: 50)
                
                if filesToVerify.isEmpty {
                    print("IntegrityManager: No files need verification, waiting...")
                    try await Task.sleep(for: .seconds(3600)) // Wait 1 hour
                    continue
                }
                
                print("IntegrityManager: Verifying \(filesToVerify.count) files")
                
                // Verify each file
                for (path, expectedHash) in filesToVerify {
                    guard isRunning else { break }
                    
                    // Determine which provider to use based on path prefix
                    let provider: VaultProvider?
                    if path.hasPrefix("drive/") {
                        provider = driveProvider
                    } else if path.hasPrefix("photos/") {
                        provider = photoProvider
                    } else {
                        provider = driveProvider // Default to drive
                    }
                    
                    guard let vaultProvider = provider else {
                        print("IntegrityManager: No provider for \(path)")
                        continue
                    }
                    
                    await verifyFile(path: path, expectedHash: expectedHash, provider: vaultProvider)
                    
                    // Small delay between verifications to avoid overwhelming the system
                    try? await Task.sleep(for: .milliseconds(100))
                }
                
                // Update stats after batch
                await MainActor.run {
                    self.updateStats()
                }
                
                // Wait before next batch
                try await Task.sleep(for: .seconds(60)) // Wait 1 minute between batches
                
            } catch {
                print("IntegrityManager: Error in verification loop: \(error)")
                try? await Task.sleep(for: .seconds(300)) // Wait 5 minutes on error
            }
        }
    }
    
    /// Verifies a single file's integrity
    private func verifyFile(path: String, expectedHash: String, provider: VaultProvider) async {
        do {
            let metadata = try await provider.getMetadata(for: path)
            
            guard let remoteHash = metadata["original-sha256"] else {
                // Metadata missing - file might be old or metadata not stored
                print("IntegrityManager: ⚠️ Metadata missing for \(path)")
                ledger.updateVerificationStatus(path: path, status: 3, date: Date()) // Missing
                return
            }
            
            if remoteHash == expectedHash {
                // Hashes match - verified!
                print("IntegrityManager: ✅ Verified \(path)")
                ledger.updateVerificationStatus(path: path, status: 1, date: Date()) // Verified
            } else {
                // Hashes don't match - mismatch detected!
                print("IntegrityManager: ❌ MISMATCH detected for \(path)")
                print("  Expected: \(expectedHash)")
                print("  Remote:   \(remoteHash)")
                ledger.updateVerificationStatus(path: path, status: 2, date: Date()) // Mismatch
                
                // Send notification for critical integrity issue
                NotificationManager.shared.send(
                    title: "Integrity Mismatch Detected",
                    body: "File '\(path)' has a hash mismatch. Backup may be corrupted.",
                    type: .vaultIssue
                )
            }
            
        } catch {
            print("IntegrityManager: Error verifying \(path): \(error)")
            // Don't update status on error - will retry later
        }
    }
    
    /// Performs a one-time verification of a specific file
    func verifySingleFile(path: String, provider: VaultProvider) async -> Bool {
        // Get expected hash from ledger
        // Note: This would require adding a method to SQLiteLedger to fetch a single file's hash
        // For now, this is a placeholder for future expansion
        return false
    }
}
