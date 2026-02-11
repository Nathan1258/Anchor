//
//  PersistenceManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import Photos
import Combine

@MainActor
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
    private let kDesktopBookmark = "anchor_desktop_bookmark"
    private let kDocumentsBookmark = "anchor_documents_bookmark"
    
    private let kBackupMode = "anchor_backup_mode"
    private let kSnapshotFrequency = "anchor_snapshot_freq"
    private let kAutoPrune = "anchor_auto_prune"
    
    private let kIsDriveEnabled = "anchor_is_drive_enabled"
    private let kIsPhotosEnabled = "anchor_is_photos_enabled"
    
    private let kNotifyBackupComplete = "anchor_notify_backup_complete"
    private let kNotifyVaultIssue = "anchor_notify_vault_issue"
    private let kWebhookURL = "anchor_webhook_url"
    private let kWebhookBackupComplete = "anchor_webhook_backup_complete"
    private let kWebhookBackupFailed = "anchor_webhook_backup_failed"
    private let kWebhookVaultIssue = "anchor_webhook_vault_issue"
    private let kWebhookIntegrityMismatch = "anchor_webhook_integrity_mismatch"
    private let kWebhookIntegrityError = "anchor_webhook_integrity_error"
    
    private let kIgnoredExtensions = "anchor_ignore_ext"
    private let kIgnoredFolders = "anchor_ignore_folders"
    private let kIgnoredPaths = "anchor_ignore_paths"
    
    private let kPausedUntil = "anchor_paused_until"
    
    private let kS3SecretKey = "anchor_s3_secret_key"
    
    private let kDriveScheduleMode = "anchor_drive_schedule_mode"
    private let kDriveScheduleInterval = "anchor_drive_schedule_interval"
    private let kPhotosScheduleMode = "anchor_photos_schedule_mode"
    private let kPhotosScheduleInterval = "anchor_photos_schedule_interval"
    
    private let kMaxUploadSpeedMBps = "anchor_max_upload_speed_mbps"
    private let kPauseOnExpensiveNetwork = "anchor_pause_on_expensive_network"
    
    private let kMetricsServerEnabled = "anchor_metrics_server_enabled"
    private let kMetricsServerPort = "anchor_metrics_server_port"
    
    
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
            guard defaults.object(forKey: kNotifyVaultIssue) != nil else { return true }
            return defaults.bool(forKey: kNotifyVaultIssue)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kNotifyVaultIssue) }
    }
    
    var webhookURL: String {
        get { defaults.string(forKey: kWebhookURL) ?? "" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kWebhookURL) }
    }
    
    var webhookBackupComplete: Bool {
        get {
            guard defaults.object(forKey: kWebhookBackupComplete) != nil else { return true }
            return defaults.bool(forKey: kWebhookBackupComplete)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kWebhookBackupComplete) }
    }
    
    var webhookBackupFailed: Bool {
        get {
            guard defaults.object(forKey: kWebhookBackupFailed) != nil else { return true }
            return defaults.bool(forKey: kWebhookBackupFailed)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kWebhookBackupFailed) }
    }
    
    var webhookVaultIssue: Bool {
        get {
            guard defaults.object(forKey: kWebhookVaultIssue) != nil else { return true }
            return defaults.bool(forKey: kWebhookVaultIssue)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kWebhookVaultIssue) }
    }
    
    var webhookIntegrityMismatch: Bool {
        get {
            guard defaults.object(forKey: kWebhookIntegrityMismatch) != nil else { return true }
            return defaults.bool(forKey: kWebhookIntegrityMismatch)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kWebhookIntegrityMismatch) }
    }
    
    var webhookIntegrityError: Bool {
        get {
            guard defaults.object(forKey: kWebhookIntegrityError) != nil else { return true }
            return defaults.bool(forKey: kWebhookIntegrityError)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kWebhookIntegrityError) }
    }
    
    var maxUploadSpeedMBps: Double {
        get {
            let value = defaults.double(forKey: kMaxUploadSpeedMBps)
            return value == 0 ? 0 : value
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kMaxUploadSpeedMBps) }
    }
    
    var pauseOnExpensiveNetwork: Bool {
        get {
            guard defaults.object(forKey: kPauseOnExpensiveNetwork) != nil else { return false }
            return defaults.bool(forKey: kPauseOnExpensiveNetwork)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kPauseOnExpensiveNetwork) }
    }
    
    var metricsServerEnabled: Bool {
        get {
            guard defaults.object(forKey: kMetricsServerEnabled) != nil else { return false }
            return defaults.bool(forKey: kMetricsServerEnabled)
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kMetricsServerEnabled) }
    }
    
    var metricsServerPort: Int {
        get {
            let port = defaults.integer(forKey: kMetricsServerPort)
            return port == 0 ? 9099 : port
        }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kMetricsServerPort) }
    }
    
    var s3Config: S3Config {
        get {
            guard let data = defaults.data(forKey: kS3Config),
                  var config = try? JSONDecoder().decode(S3Config.self, from: data) else {
                return S3Config()
            }
            
            if let secret = KeychainManager.shared.load(key: kS3SecretKey) {
                config.secretKey = secret
            }
            
            return config
        }
        set {
            objectWillChange.send()
            
            if !newValue.secretKey.isEmpty {
                KeychainManager.shared.save(key: kS3SecretKey, value: newValue.secretKey)
            } else {
                KeychainManager.shared.delete(key: kS3SecretKey)
            }
            
            var sanitizedConfig = newValue
            sanitizedConfig.secretKey = ""
            
            if let data = try? JSONEncoder().encode(sanitizedConfig) {
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
    
    var ignoredPaths: [String] {
        get { defaults.stringArray(forKey: kIgnoredPaths) ?? [] }
        set { objectWillChange.send(); defaults.set(newValue, forKey: kIgnoredPaths) }
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
    
    var driveScheduleMode: BackupScheduleMode {
        get {
            let raw = defaults.integer(forKey: kDriveScheduleMode)
            return BackupScheduleMode(rawValue: raw) ?? .realtime
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kDriveScheduleMode)
        }
    }
    
    var driveScheduleInterval: BackupScheduleInterval {
        get {
            let raw = defaults.integer(forKey: kDriveScheduleInterval)
            return BackupScheduleInterval(rawValue: raw) ?? .hourly
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kDriveScheduleInterval)
        }
    }
    
    var photosScheduleMode: BackupScheduleMode {
        get {
            let raw = defaults.integer(forKey: kPhotosScheduleMode)
            return BackupScheduleMode(rawValue: raw) ?? .realtime
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kPhotosScheduleMode)
        }
    }
    
    var photosScheduleInterval: BackupScheduleInterval {
        get {
            let raw = defaults.integer(forKey: kPhotosScheduleInterval)
            return BackupScheduleInterval(rawValue: raw) ?? .hourly
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.rawValue, forKey: kPhotosScheduleInterval)
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
            case .desktopFolder: defaults.set(data, forKey: kDesktopBookmark)
            case .documentsFolder: defaults.set(data, forKey: kDocumentsBookmark)
            }
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }
    
    func clearBookmark(type: BookmarkType) {
        switch type {
        case .driveSource: defaults.removeObject(forKey: kSourceBookmark)
        case .driveVault: defaults.removeObject(forKey: kVaultBookmark)
        case .photoVault: defaults.removeObject(forKey: kPhotoVaultBookmark)
        case .desktopFolder: defaults.removeObject(forKey: kDesktopBookmark)
        case .documentsFolder: defaults.removeObject(forKey: kDocumentsBookmark)
        }
    }
    
    
    func loadBookmark(type: BookmarkType) -> URL? {
        let key: String
        switch type {
        case .driveSource: key = kSourceBookmark
        case .driveVault: key = kVaultBookmark
        case .photoVault: key = kPhotoVaultBookmark
        case .desktopFolder: key = kDesktopBookmark
        case .documentsFolder: key = kDocumentsBookmark
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
        case desktopFolder
        case documentsFolder
    }
}
