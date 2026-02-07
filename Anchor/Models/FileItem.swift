//
//  FileItem.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//
import Foundation

struct FileItem: Identifiable, Hashable {
    var id: String { fullPath }
    
    let name: String
    let fullPath: String
    let isFolder: Bool
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        return lhs.fullPath == rhs.fullPath
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fullPath)
    }
}
