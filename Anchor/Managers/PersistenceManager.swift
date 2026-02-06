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
    
    private let kDriveVaultType = "anchor_drive_vault_type"
    private let kPhotoVaultType = "anchor_photo_vault_type"
    private let kS3Config = "anchor_s3_config"
    
    private let kSourceBookmark = "anchor_source_bookmark"
    private let kVaultBookmark = "anchor_vault_bookmark"
    private let kPhotoVaultBookmark = "anchor_photo_vault_bookmark"
    private let kPhotoChangeToken = "anchor_photo_change_token"
    
    private let kBackupMode = "anchor_backup_mode"
    private let kSnapshotFrequency = "anchor_snapshot_freq"
    private let kAutoPrune = "anchor_auto_prune"
    
    private let kIsDriveEnabled = "anchor_is_drive_enabled"
    private let kIsPhotosEnabled = "anchor_is_photos_enabled"
    
    private let kNotifyBackupComplete = "anchor_notify_backup_complete"
    private let kNotifyVaultIssue = "anchor_notify_vault_issue"
    
    private let kIgnoredExtensions = "anchor_ignore_ext"
    private let kIgnoredFolders = "anchor_ignore_folders"
    
    private let kPausedUntil = "anchor_paused_until"
    
    var backupMode: BackupMode {
        get {
            let raw = defaults.integer(forKey: kBackupMode)
            return BackupMode(rawValue: raw) ?? .basic
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kBackupMode)
        }
    }
    
    var snapshotFrequency: Int {
        get {
            let val = defaults.integer(forKey: kSnapshotFrequency)
            return val == 0 ? 60 : val
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: kSnapshotFrequency)
        }
    }
    
    var driveVaultType: VaultType {
        get {
            guard let raw = defaults.string(forKey: kDriveVaultType) else { return .local }
            return VaultType(rawValue: raw) ?? .local
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kDriveVaultType)
        }
    }
    
    var photoVaultType: VaultType {
        get {
            guard let raw = defaults.string(forKey: kPhotoVaultType) else { return .local }
            return VaultType(rawValue: raw) ?? .local
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kPhotoVaultType)
        }
    }
    
    var notifyVaultIssue: Bool {
        get {
            guard let val = defaults.object(forKey: kNotifyVaultIssue) else { return true }
            return defaults.bool(forKey: kNotifyVaultIssue)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kNotifyVaultIssue) }
    }
    
    var s3Config: S3Config {
        get {
            guard let data = defaults.data(forKey: kS3Config),
                  let config = try? JSONDecoder().decode(S3Config.self, from: data) else {
                return S3Config()
            }
            return config
        }
        set {
            objectWillChange.send()
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: kS3Config)
            }
        }
    }
    
    var autoPrune: Bool {
        get {
            if defaults.object(forKey: kAutoPrune) == nil { return true }
            return defaults.bool(forKey: kAutoPrune)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: kAutoPrune)
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
    
    var pausedUntil: Date? {
        get { defaults.object(forKey: kPausedUntil) as? Date }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: kPausedUntil)
        }
    }
    
    var isGlobalPaused: Bool {
        guard let date = pausedUntil else { return false }
        return Date() < date
    }
    
    func clearPhotoToken() {
        defaults.removeObject(forKey: kPhotoChangeToken)
    }
    
    var ignoredExtensions: [String] {
        get { defaults.stringArray(forKey: kIgnoredExtensions) ?? [] }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kIgnoredExtensions) }
    }
    
    var ignoredFolders: [String] {
        get { defaults.stringArray(forKey: kIgnoredFolders) ?? [] }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kIgnoredFolders) }
    }
    
    var notifyBackupComplete: Bool {
        get { defaults.object(forKey: kNotifyBackupComplete) == nil ? false : defaults.bool(forKey: kNotifyBackupComplete) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kNotifyBackupComplete) }
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
