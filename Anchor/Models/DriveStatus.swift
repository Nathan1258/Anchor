//
//  Status.swift
//  Anchor
//
//  Created by Nathan Ellis on 05/02/2026.
//
import Foundation

enum DriveStatus: Equatable {
    case idle
    case disabled
    case waitingForVault
    case active
    case scanning
    case monitoring
    case newItem
    case changeDetected
    case downloading(filename: String)
    case vaulted(filename: String)
    case deleted(filename: String)
    
    var label: String {
        switch self {
        case .idle: return "Idle"
        case .disabled: return "Disabled"
        case .waitingForVault: return "Waiting for Vault..."
        case .active: return "Watcher Active"
        case .scanning: return "Performing Smart Scan..."
        case .monitoring: return "Monitoring Active"
        case .newItem: return "New item detected..."
        case .changeDetected: return "Change detected..."
        case .downloading(let filename): return "Downloading \(filename)..."
        case .vaulted(let filename): return "Vaulted \(filename)"
        case .deleted(let filename): return "Deleted \(filename)"
        }
    }
}
