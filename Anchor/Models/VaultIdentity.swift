//
//  VaultIdentity.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

struct VaultIdentity: Codable {
    let vaultID: UUID
    
    let salt: Data?
    
    let verificationToken: Data?
    
    init(vaultID: UUID, salt: Data? = nil, verificationToken: Data? = nil) {
        self.vaultID = vaultID
        self.salt = salt
        self.verificationToken = verificationToken
    }
}
