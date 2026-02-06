//
//  VaultProvider.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

protocol VaultProvider {
    /// Saves a file to the vault.
    /// - Parameters:
    ///   - source: The local URL of the file to upload/copy.
    ///   - relativePath: The path where it should live (e.g., "2026/02/photo.jpg").
    func saveFile(source: URL, relativePath: String) async throws
    
    /// Deletes a file from the vault.
    func deleteFile(relativePath: String) async throws
    
    /// Checks if a file exists (Optional optimization, avoiding re-uploads).
    func fileExists(relativePath: String) async -> Bool
}

class VaultFactory {
    static func getProvider(type: VaultType) async throws -> VaultProvider? {
        switch type {
        case .local:
            if let vaultURL = PersistenceManager.shared.loadBookmark(type: .driveVault) {
                return LocalVault(rootURL: vaultURL)
            }
            return nil
            
        case .s3:
            let config = PersistenceManager.shared.s3Config
            if config.isValid {
                return try await S3Vault.create(config: config)
            }
            return nil
        }
    }
}
