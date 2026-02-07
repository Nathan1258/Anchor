//
//  ReIndexManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//
import Foundation
import SwiftUI
import Combine

class ReIndexManager: ObservableObject {
    static let shared = ReIndexManager()
    
    @Published var isIndexing = false
    @Published var statusMessage = ""
    
    private init() {}
    
    func rebuildIndex(type: VaultType) {
        guard !isIndexing else { return }
        isIndexing = true
        statusMessage = "Connecting to Vault..."
        
        Task {
            do {
                guard let provider = try await VaultFactory.getProvider(type: type) else {
                    finish("Could not connect to provider.")
                    return
                }
                
                await MainActor.run { statusMessage = "Scanning remote files..." }
                
                let allPaths = try await provider.listAllFiles()
                
                await MainActor.run { statusMessage = "Importing \(allPaths.count) items..." }
                
                let ledger = SQLiteLedger()
                
                ledger.wipe() 
                
                for path in allPaths {
                    if path == "anchor_identity.json" { continue }
                    if path.hasSuffix(".DS_Store") { continue }
                    
                    var logicalPath = path
                    if path.hasSuffix(".anchor") {
                        logicalPath = String(path.dropLast(7))
                    }
                    
                    ledger.markAsProcessed(relativePath: logicalPath, genID: "imported")
                }
                
                finish("✅ Index Rebuilt: \(allPaths.count) files found.")
                
            } catch {
                finish("❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func finish(_ msg: String) {
        DispatchQueue.main.async {
            self.statusMessage = msg
            self.isIndexing = false
            
            if msg.starts(with: "✅") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if self.statusMessage == msg { self.statusMessage = "" }
                }
            }
        }
    }
}
