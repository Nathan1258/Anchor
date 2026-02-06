//
//  S3Config.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//

import Foundation

enum VaultType: String, CaseIterable, Identifiable {
    case local = "Local Drive"
    case s3 = "S3 / Cloud Object Storage"
    
    var id: String { self.rawValue }
}

struct S3Config: Codable, Equatable {
    var endpoint: String = "https://s3.amazonaws.com"
    var region: String = "us-east-1"
    var bucket: String = ""
    var accessKey: String = ""
    var secretKey: String = ""
    
    var isValid: Bool {
        !bucket.isEmpty && !accessKey.isEmpty && !secretKey.isEmpty
    }
}

