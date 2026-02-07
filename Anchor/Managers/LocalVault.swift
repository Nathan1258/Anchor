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
    
    func downloadFile(relativePath: String, to localURL: URL) async throws {
        let sourceURL = rootURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: localURL)
    }
    
    func listFiles(at path: String) async throws -> [FileMetadata] {
        let targetURL = path.isEmpty ? rootURL : rootURL.appendingPathComponent(path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        
        let keys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        
        let urls = try FileManager.default.contentsOfDirectory(
            at: targetURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        
        return urls.compactMap { url -> FileMetadata? in
            guard let resources = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            
            let name = resources.name ?? url.lastPathComponent
            let relativePath = path.isEmpty ? name : "\(path)/\(name)"
            
            return FileMetadata(
                name: name,
                path: relativePath,
                isFolder: resources.isDirectory ?? false,
                size: resources.fileSize ?? 0,
                lastModified: resources.contentModificationDate
            )
        }
    }
    
    func listAllFiles() async throws -> [String] {
        var paths: [String] = []
        if let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                let path = fileURL.path
                let root = rootURL.path
                if path.hasPrefix(root) {
                    var relative = String(path.dropFirst(root.count))
                    if relative.hasPrefix("/") { relative.removeFirst() }
                    paths.append(relative)
                }
            }
        }
        return paths
    }
    
    func wipe(prefix: String) async throws {
        let targetURL = prefix.isEmpty ? rootURL : rootURL.appendingPathComponent(prefix)
        
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return }
        
        if prefix.isEmpty {
            let contents = try FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil)
            for url in contents {
                if url.lastPathComponent == "anchor_identity.json" { continue }
                try FileManager.default.removeItem(at: url)
            }
        } else {
            try FileManager.default.removeItem(at: targetURL)
        }
        
        print("Local Wipe Complete: \(targetURL.lastPathComponent)")
    }
    
    func saveFile(source: URL, relativePath: String, checkCancellation: (() -> Bool)? = nil) async throws {
        if let checkCancellation, checkCancellation(){
            throw NSError(domain: "Anchor", code: 999, userInfo: [NSLocalizedDescriptionKey: "Copy Cancelled"])
        }
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
        print("Local Copy Success: \(relativePath)")
    }
    
    func deleteFile(relativePath: String) async throws {
        let destURL = rootURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
            print("Local Delete Success: \(relativePath)")
        }
    }
    
    func moveItem(from oldPath: String, to newPath: String) async throws {
        let src = rootURL.appendingPathComponent(oldPath)
        let dst = rootURL.appendingPathComponent(newPath)
        
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        try FileManager.default.moveItem(at: src, to: dst)
        print("Local Move Success: \(oldPath) -> \(newPath)")
    }
    
    func fileExists(relativePath: String) async -> Bool {
        let destURL = rootURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: destURL.path)
    }
}
