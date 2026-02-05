//
//  NotificationManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 05/02/2026.
//
import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func send(title: String, body: String, type: NotificationType) {
        switch type {
        case .backupComplete:
            guard PersistenceManager.shared.notifyBackupComplete else { return }
        case .vaultIssue:
            guard PersistenceManager.shared.notifyVaultIssue else { return }
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    enum NotificationType {
        case backupComplete
        case vaultIssue
    }
}
