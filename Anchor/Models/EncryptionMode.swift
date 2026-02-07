//
//  EncryptionMode.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

enum EncryptionMode {
    case setup(VaultIdentity?)
    case unlock(VaultIdentity)
}

extension EncryptionMode: Identifiable {
    var id: String {
        switch self {
        case .setup: return "setup"
        case .unlock: return "unlock"
        }
    }
}
