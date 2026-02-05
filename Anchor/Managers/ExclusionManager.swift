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
        "node_modules",
        ".git",
        ".svn",
        ".DS_Store",
        "Thumbs.db",
        "Desktop.ini",
        "__MACOSX"
    ]
    
    private let systemIgnoredPrefixes: [String] = [
        "~$"
    ]
    
    private let systemIgnoredExtensions: Set<String> = [
        "tmp",
        "temp",
        "swp",
        "lock"
    ]
    
    @Published var userIgnoredExtensions: [String] = []
    @Published var userIgnoredFolderNames: [String] = []
        
    private init() {
        loadRules()
    }
    
    func loadRules() {
        userIgnoredExtensions = UserDefaults.standard.stringArray(forKey: "anchor_ignore_ext") ?? []
        userIgnoredFolderNames = UserDefaults.standard.stringArray(forKey: "anchor_ignore_folders") ?? []
    }
    
    func addExtension(_ ext: String) {
        let clean = ext.replacingOccurrences(of: ".", with: "").lowercased()
        if !userIgnoredExtensions.contains(clean) {
            userIgnoredExtensions.append(clean)
            UserDefaults.standard.set(userIgnoredExtensions, forKey: "anchor_ignore_ext")
        }
    }
    
    func addFolder(_ name: String) {
        if !userIgnoredFolderNames.contains(name) {
            userIgnoredFolderNames.append(name)
            UserDefaults.standard.set(userIgnoredFolderNames, forKey: "anchor_ignore_folders")
        }
    }
    
    func shouldIgnore(url: URL) -> Bool {
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        
        if systemIgnoredNames.contains(filename) { return true }
        if userIgnoredFolderNames.contains(filename) { return true }
        
        for prefix in systemIgnoredPrefixes {
            if filename.hasPrefix(prefix) { return true }
        }
        
        if !ext.isEmpty {
            if systemIgnoredExtensions.contains(ext) { return true }
            if userIgnoredExtensions.contains(ext) { return true }
        }
        
        let components = url.pathComponents
        
        for component in components {
            if systemIgnoredNames.contains(component) { return true }
            if userIgnoredFolderNames.contains(component) { return true }
        }
        
        return false
    }
}
