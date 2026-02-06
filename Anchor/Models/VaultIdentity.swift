//
//  VaultIdentity.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

struct VaultIdentity: Codable {
    /// Random data used to salt the password hash. Publicly visible.
    let salt: Data
    
    /// A UUID to verify we are looking at the right vault.
    let vaultID: UUID
    
    /// A check hash to verify the password is correct without decrypting files.
    /// We encrypt the string "ANCHOR_VERIFY" using the key. 
    /// If we can decrypt it later, the password is correct.
    let verificationToken: Data
}
