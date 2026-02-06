//
//  CryptoError.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

enum CryptoError: Error {
    case noKeyConfigured, corruptHeader, corruptData, fileTooLarge, invalidPassword, keyDerivationFailed
}
