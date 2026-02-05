//
//  BackupMode.swift
//  Anchor
//
//  Created by Nathan Ellis on 05/02/2026.
//
import Foundation

enum BackupMode: Int, CaseIterable, Identifiable {
    case basic = 0    // Deletions in cloud are ignored (kept in vault)
    case mirror = 1   // Deletions in cloud = Deletions in vault
    case snapshot = 2 // History preserved
    
    var id: Int { self.rawValue }
}
