//
//  VaultError.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

enum VaultError: LocalizedError {
    case diskFull(required: Int64, available: Int64)
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .diskFull(let req, let avail):
            return "Destination drive is full. Required: \(ByteCountFormatter.string(fromByteCount: req, countStyle: .file)), Available: \(ByteCountFormatter.string(fromByteCount: avail, countStyle: .file))"
        case .networkUnavailable:
            return "Upload paused: Connected to expensive network (hotspot/cellular)"
        }
    }
}
