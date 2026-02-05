//
//  PersistenceManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import Photos
import Combine

class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()
    
    private let defaults = UserDefaults.standard
    
    private let kSourceBookmark = "anchor_source_bookmark"
    private let kVaultBookmark = "anchor_vault_bookmark"
    private let kPhotoVaultBookmark = "anchor_photo_vault_bookmark"
    private let kPhotoChangeToken = "anchor_photo_change_token"
    private let kMirrorDeletions = "anchor_mirror_deletions"
    
    private let kIsDriveEnabled = "anchor_is_drive_enabled"
    private let kIsPhotosEnabled = "anchor_is_photos_enabled"
    
    private let kNotifyBackupComplete = "anchor_notify_backup_complete"
    private let kNotifyVaultIssue = "anchor_notify_vault_issue"
    
    var mirrorDeletions: Bool {
        get { defaults.bool(forKey: kMirrorDeletions) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: kMirrorDeletions)
        }
    }
    
    var isDriveEnabled: Bool {
        get {
            if defaults.object(forKey: kIsDriveEnabled) == nil { return false }
            return defaults.bool(forKey: kIsDriveEnabled)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: kIsDriveEnabled)
        }
    }
    
    var notifyBackupComplete: Bool {
        get { defaults.object(forKey: kNotifyBackupComplete) == nil ? false : defaults.bool(forKey: kNotifyBackupComplete) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kNotifyBackupComplete) }
    }
    
    var notifyVaultIssue: Bool {
        get { defaults.object(forKey: kNotifyVaultIssue) == nil ? false : defaults.bool(forKey: kNotifyVaultIssue) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kNotifyVaultIssue) }
    }
    
    var isPhotosEnabled: Bool {
        get {
            if defaults.object(forKey: kIsPhotosEnabled) == nil { return false }
            return defaults.bool(forKey: kIsPhotosEnabled)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: kIsPhotosEnabled)
        }
    }
    
    
    func savePhotoToken(_ token: PHPersistentChangeToken) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            defaults.set(data, forKey: kPhotoChangeToken)
        } catch {
            print("Failed to archive token: \(error)")
        }
    }
    
    func loadPhotoToken() -> PHPersistentChangeToken? {
        guard let data = defaults.data(forKey: kPhotoChangeToken) else { return nil }
        do {
            let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
            return token
        } catch {
            print("Failed to unarchive token: \(error)")
            return nil
        }
    }
    
    
    func saveBookmark(for url: URL, type: BookmarkType) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            
            switch type {
            case .driveSource: defaults.set(data, forKey: kSourceBookmark)
            case .driveVault: defaults.set(data, forKey: kVaultBookmark)
            case .photoVault: defaults.set(data, forKey: kPhotoVaultBookmark)
            }
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }
    
    
    func loadBookmark(type: BookmarkType) -> URL? {
        let key: String
        switch type {
        case .driveSource: key = kSourceBookmark
        case .driveVault: key = kVaultBookmark
        case .photoVault: key = kPhotoVaultBookmark
        }
        
        guard let data = defaults.data(forKey: key) else { return nil }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("Bookmark is stale for \(key)")
            }
            return url
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }
    
    enum BookmarkType {
        case driveSource
        case driveVault
        case photoVault
    }
}
