//
//  VaultProvider.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

protocol VaultProvider: Sendable {
    /// Saves a file to the vault.
    func saveFile(source: URL, relativePath: String, checkCancellation: (() -> Bool)?) async throws
    
    /// Lists all objects (or files if local)
    func listAllFiles() async throws -> [String]
    
    /// Lists all obejcts (or files if local) at a specific directory
    func listFiles(at path: String) async throws -> [FileMetadata] // Cannot find type 'FileMetadata' in scope
    
    /// Deletes a file from the vault.
    func deleteFile(relativePath: String) async throws
    
    /// Checks if a file exists (Optional optimization, avoiding re-uploads).
    func fileExists(relativePath: String) async -> Bool
    
    func moveItem(from oldPath: String, to newPath: String) async throws
    
    /// Checks for '.anchor_identity.json' in the root.
    func loadIdentity() async throws -> VaultIdentity?
    
    /// Saves the lock file during setup.
    func saveIdentity(_ identity: VaultIdentity) async throws
    
    /// Loads the photo library persistent token from the vault.
    func loadPhotoToken() async throws -> Data?
    
    /// Saves the photo library persistent token to the vault.
    func savePhotoToken(_ tokenData: Data) async throws
    
    /// Downloads specific file to temporary directory for restoring
    func downloadFile(relativePath: String, to localURL: URL) async throws
    
    /// Deletes all files/photos
    func wipe(prefix: String) async throws
}

class VaultFactory {
    static func getProvider(type: VaultType, bookmarkType: PersistenceManager.BookmarkType? = nil) async throws -> VaultProvider? {
        switch type {
        case .local:
            let bookmark = bookmarkType ?? .driveVault
            if let vaultURL = PersistenceManager.shared.loadBookmark(type: bookmark) {
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
