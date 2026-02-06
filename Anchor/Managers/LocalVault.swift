//
//  LocalVault.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

final class LocalVault: VaultProvider {
    
    private let rootURL: URL
    
    init(rootURL: URL) {
        self.rootURL = rootURL
    }
    
    func loadIdentity() async throws -> VaultIdentity? {
        let identityURL = rootURL.appendingPathComponent("anchor_identity.json")
        
        guard FileManager.default.fileExists(atPath: identityURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: identityURL)
        return try JSONDecoder().decode(VaultIdentity.self, from: data)
    }
    
    func saveIdentity(_ identity: VaultIdentity) async throws {
        let identityURL = rootURL.appendingPathComponent("anchor_identity.json")
        let data = try JSONEncoder().encode(identity)
        try data.write(to: identityURL)
    }
    
    func saveFile(source: URL, relativePath: String) async throws {
        let destURL = rootURL.appendingPathComponent(relativePath)
        
        let resources = try source.resourceValues(forKeys: [.fileSizeKey])
        let requiredSpace = Int64(resources.fileSize ?? 0)
        
        let values = try rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < requiredSpace {
            throw VaultError.diskFull(required: requiredSpace, available: available)
        }
        
        try FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        
        try FileManager.default.copyItem(at: source, to: destURL)
        print("📂 Local Copy Success: \(relativePath)")
    }
    
    func deleteFile(relativePath: String) async throws {
        let destURL = rootURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
            print("🗑️ Local Delete Success: \(relativePath)")
        }
    }
    
    func moveItem(from oldPath: String, to newPath: String) async throws {
        let src = rootURL.appendingPathComponent(oldPath)
        let dst = rootURL.appendingPathComponent(newPath)
        
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        try FileManager.default.moveItem(at: src, to: dst)
        print("📂 Local Move Success: \(oldPath) -> \(newPath)")
    }
    
    func fileExists(relativePath: String) async -> Bool {
        let destURL = rootURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: destURL.path)
    }
}
