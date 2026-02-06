//
//  LocalVault.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

class LocalVault: VaultProvider {
    
    private let rootURL: URL
    
    init(rootURL: URL) {
        self.rootURL = rootURL
    }
    
    func saveFile(source: URL, relativePath: String) async throws {
        let destURL = rootURL.appendingPathComponent(relativePath)
        
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
    
    func fileExists(relativePath: String) async -> Bool {
        let destURL = rootURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: destURL.path)
    }
}
