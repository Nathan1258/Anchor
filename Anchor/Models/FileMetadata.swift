//
//  FileMetadata.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//
import Foundation

struct FileMetadata: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String 
    let isFolder: Bool
    let size: Int?
    let lastModified: Date?
}
