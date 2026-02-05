//
//  PhotosStatus.swift
//  Anchor
//
//  Created by Nathan Ellis on 05/02/2026.
//
import Foundation

enum PhotosStatus: Equatable {
    case waiting
    case disabled
    case paused
    case waitingForVault
    case waitingForStatus
    case accessDenied
    case monitoring
    case checkingForChanges
    case synced(count: Int)
    case upToDate
    case scanning
    case processing(current: Int, total: Int)
    case backupComplete
    
    var label: String {
        switch self {
        case .waiting: return "Waiting to start..."
        case .disabled: return "Disabled"
        case .paused: return "Paused"
        case .accessDenied: return "Access Denied"
        case .waitingForVault: return "Waiting for Vault..."
        case .waitingForStatus: return "Waiting for Photos Library to update..."
        case .monitoring: return "Monitoring Library"
        case .checkingForChanges: return "Checking for new photos..."
        case .synced(let count): return "Synced \(count) new items"
        case .upToDate: return "Up to date"
        case .scanning: return "Scanning entire library..."
        case .processing(let current, let total): return "Processing \(current)/\(total)..."
        case .backupComplete: return "Full Backup Complete"
        }
    }
}
