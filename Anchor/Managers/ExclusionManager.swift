//
//  ExclusionManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import Combine

class ExclusionManager: ObservableObject {
    static let shared = ExclusionManager()
    
    private let systemIgnoredNames: Set<String> = [
        "node_modules", ".git", ".svn", ".DS_Store",
        "Thumbs.db", "Desktop.ini", "__MACOSX"
    ]
    
    private let systemIgnoredPrefixes: [String] = ["~$"]
    
    private let systemIgnoredExtensions: Set<String> = [
        "tmp", "temp", "swp", "lock"
    ]
    
    var userIgnoredExtensions: [String] { PersistenceManager.shared.ignoredExtensions }
    var userIgnoredFolderNames: [String] { PersistenceManager.shared.ignoredFolders }
    
    private init() {}
        
    func addExtension(_ ext: String) {
        let clean = ext.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }
        
        var current = PersistenceManager.shared.ignoredExtensions
        if !current.contains(clean) {
            current.append(clean)
            PersistenceManager.shared.ignoredExtensions = current
        }
    }
    
    func removeExtension(_ ext: String) {
        var current = PersistenceManager.shared.ignoredExtensions
        current.removeAll { $0 == ext }
        PersistenceManager.shared.ignoredExtensions = current
    }
    
    func addFolder(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        
        var current = PersistenceManager.shared.ignoredFolders
        if !current.contains(clean) {
            current.append(clean)
            PersistenceManager.shared.ignoredFolders = current
        }
    }
    
    func removeFolder(_ name: String) {
        var current = PersistenceManager.shared.ignoredFolders
        current.removeAll { $0 == name }
        PersistenceManager.shared.ignoredFolders = current
    }
    
    
    func shouldIgnore(url: URL) -> Bool {
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        
        if systemIgnoredNames.contains(filename) { return true }
        for prefix in systemIgnoredPrefixes {
            if filename.hasPrefix(prefix) { return true }
        }
        if !ext.isEmpty && systemIgnoredExtensions.contains(ext) { return true }
        
        if userIgnoredFolderNames.contains(filename) { return true }
        if !ext.isEmpty && userIgnoredExtensions.contains(ext) { return true }
        
        let components = url.pathComponents
        for component in components {
            if systemIgnoredNames.contains(component) { return true }
            if userIgnoredFolderNames.contains(component) { return true }
        }
        
        return false
    }
}
