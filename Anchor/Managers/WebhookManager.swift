//
//  WebhookManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 11/02/2026.
//

import Foundation
import Combine

/// Webhook event types
enum WebhookEventType: String, Codable, CaseIterable {
    case backupComplete = "backup_complete"
    case backupFailed = "backup_failed"
    case vaultIssue = "vault_issue"
    case integrityMismatch = "integrity_mismatch"
    case integrityError = "integrity_error"
    case test = "test"
    
    var displayName: String {
        switch self {
        case .backupComplete: return "Backup Completed"
        case .backupFailed: return "Backup Failed"
        case .vaultIssue: return "Vault Issues"
        case .integrityMismatch: return "Integrity Mismatch Detected"
        case .integrityError: return "Integrity Verification Errors"
        case .test: return "Test Webhook"
        }
    }
}

/// Backup type for webhook events
enum WebhookBackupType: String, Codable {
    case drive = "drive"
    case photos = "photos"
}

/// Webhook payload structure
struct WebhookPayload: Codable {
    let event: WebhookEventType
    let timestamp: String
    let backupType: WebhookBackupType?
    let filesProcessed: Int?
    let errorMessage: String?
    let hostname: String
    let appVersion: String
    
    init(event: WebhookEventType, backupType: WebhookBackupType? = nil, filesProcessed: Int? = nil, errorMessage: String? = nil) {
        self.event = event
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.backupType = backupType
        self.filesProcessed = filesProcessed
        self.errorMessage = errorMessage
        self.hostname = Host.current().localizedName ?? "Unknown"
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}

/// Manages webhook notifications for backup events
@MainActor
class WebhookManager: ObservableObject {
    static let shared = WebhookManager()
    
    private init() {}
    
    /// Send a webhook notification
    func send(event: WebhookEventType, backupType: WebhookBackupType? = nil, filesProcessed: Int? = nil, errorMessage: String? = nil) {
        let webhookURL = PersistenceManager.shared.webhookURL
        
        guard !webhookURL.isEmpty,
              let url = URL(string: webhookURL) else {
            return
        }
        
        guard isEventEnabled(event) else {
            return
        }
        
        let payload = WebhookPayload(
            event: event,
            backupType: backupType,
            filesProcessed: filesProcessed,
            errorMessage: errorMessage
        )
        
        Task {
            await sendWebhook(to: url, payload: payload)
        }
    }
    
    /// Check if a webhook event type is enabled
    private func isEventEnabled(_ event: WebhookEventType) -> Bool {
        switch event {
        case .backupComplete:
            return PersistenceManager.shared.webhookBackupComplete
        case .backupFailed:
            return PersistenceManager.shared.webhookBackupFailed
        case .vaultIssue:
            return PersistenceManager.shared.webhookVaultIssue
        case .integrityMismatch:
            return PersistenceManager.shared.webhookIntegrityMismatch
        case .integrityError:
            return PersistenceManager.shared.webhookIntegrityError
        case .test:
            return true
        }
    }
    
    /// Test webhook connectivity
    func testWebhook(url: String) async -> (success: Bool, message: String) {
        guard !url.isEmpty,
              let webhookURL = URL(string: url) else {
            return (false, "Invalid URL format")
        }
        
        let payload = WebhookPayload(event: .test)
        
        let result = await sendWebhook(to: webhookURL, payload: payload)
        return result
    }
    
    /// Internal method to send webhook POST request
    private func sendWebhook(to url: URL, payload: WebhookPayload) async -> (success: Bool, message: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Anchor-Backup/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            request.httpBody = try encoder.encode(payload)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response from server")
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                print("✅ Webhook sent successfully: \(payload.event.rawValue)")
                return (true, "Webhook delivered successfully (HTTP \(httpResponse.statusCode))")
            } else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("⚠️ Webhook failed with status \(httpResponse.statusCode): \(errorBody)")
                return (false, "Server returned HTTP \(httpResponse.statusCode)")
            }
        } catch let error as URLError {
            let message: String
            switch error.code {
            case .notConnectedToInternet:
                message = "No internet connection"
            case .timedOut:
                message = "Request timed out"
            case .cannotFindHost:
                message = "Cannot find host"
            case .cannotConnectToHost:
                message = "Cannot connect to host"
            default:
                message = error.localizedDescription
            }
            print("⚠️ Webhook error: \(message)")
            return (false, message)
        } catch {
            print("⚠️ Webhook error: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }
}
