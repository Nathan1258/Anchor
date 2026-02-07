//
//  Utils.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

func performWithActivity<T>(_ reason: String, block: () async throws -> T) async rethrows -> T {
    let options: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
    
    let activity = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
    defer {
        ProcessInfo.processInfo.endActivity(activity)
    }
    
    return try await block()
}

func areOnSameVolume(_ url1: URL, _ url2: URL) -> Bool {
    let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
    
    guard let values1 = try? url1.resourceValues(forKeys: keys),
          let values2 = try? url2.resourceValues(forKeys: keys),
          let volume1 = values1.volumeIdentifier as? UUID,
          let volume2 = values2.volumeIdentifier as? UUID else {
        return false
    }
    
    return volume1 == volume2
}

func createSnapshotDirectory(for sourceURL: URL) -> URL {
    let systemTemp = FileManager.default.temporaryDirectory
    
    if areOnSameVolume(sourceURL, systemTemp) {
        return systemTemp.appendingPathComponent(UUID().uuidString)
    }
    
    let sourceVolume = sourceURL.deletingLastPathComponent()
    let anchorTempBase = sourceVolume.appendingPathComponent(".anchor_temp")
    let uniqueTempDir = anchorTempBase.appendingPathComponent(UUID().uuidString)
    
    do {
        try FileManager.default.createDirectory(at: uniqueTempDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
        return uniqueTempDir
    } catch {
        print("⚠️ Could not create snapshot directory on source volume: \(error). Falling back to system temp.")
        return systemTemp.appendingPathComponent(UUID().uuidString)
    }
}

func sanitizeS3Key(_ relativePath: String) -> String {
    let path = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    
    let components = path.split(separator: "/").map(String.init)
    
    let safeComponents = components.compactMap { component -> String? in
        if component == ".." || component == "." {
            print("⚠️ Security: Blocked path traversal attempt: '\(component)' in path '\(relativePath)'")
            return nil
        }
        
        if component.isEmpty {
            return nil
        }
        
        let safeCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_.() "))
        
        if component.rangeOfCharacter(from: safeCharacters.inverted) != nil {
            if let encoded = component.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.() "))) {
                return encoded
            }
        }
        
        return component
    }
    
    let sanitized = safeComponents.joined(separator: "/")
    
    if sanitized != relativePath {
        print("🔒 Sanitized S3 key: '\(relativePath)' -> '\(sanitized)'")
    }
    
    return sanitized
}

