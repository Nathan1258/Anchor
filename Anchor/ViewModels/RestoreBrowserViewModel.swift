//
//  RestoreBrowserViewModel.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//
import SwiftUI
import Combine

@MainActor
class RestoreBrowserViewModel: ObservableObject {
    @Published var currentPath: String = ""
    @Published var items: [FileItem] = []
    @Published var selectedPaths: Set<String> = []
    
    var pathComponents: [String] {
        if currentPath.isEmpty { return [] }
        return currentPath.split(separator: "/").map(String.init)
    }
    
    private let ledger = SQLiteLedger.shared
    
    init() {
        loadContent()
    }
    
    var selectedItemsCount: Int {
        selectedPaths.count
    }
    
    func loadContent() {
        let currentPath = self.currentPath
        DispatchQueue.global(qos: .userInitiated).async {
            let newItems = self.ledger.getContents(of: currentPath)
            
            DispatchQueue.main.async {
                self.items = newItems
            }
        }
    }
    
    func openFolder(_ item: FileItem) {
        if item.isFolder {
            currentPath = item.fullPath
            loadContent()
        }
    }
    
    func navigateUp() {
        if currentPath.isEmpty { return }
        
        let components = currentPath.split(separator: "/")
        if components.count > 1 {
            currentPath = components.dropLast().joined(separator: "/")
        } else {
            currentPath = ""
        }
        loadContent()
    }
    
    func navigateTo(componentIndex: Int) {
        if componentIndex < 0 { 
            currentPath = ""
        } else {
            let comps = pathComponents
            if componentIndex < comps.count {
                currentPath = comps[0...componentIndex].joined(separator: "/")
            }
        }
        loadContent()
    }
    
    func toggleSelection(_ item: FileItem) {
        if selectedPaths.contains(item.fullPath) {
            selectedPaths.remove(item.fullPath)
        } else {
            selectedPaths.insert(item.fullPath)
        }
    }
    
    func isSelected(_ item: FileItem) -> Bool {
        return selectedPaths.contains(item.fullPath)
    }
}
