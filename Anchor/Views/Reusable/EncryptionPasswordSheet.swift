//
//  EncryptionPasswordSheet.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import SwiftUI

struct EncryptionPasswordSheet: View {
    @Environment(\.dismiss) var dismiss
    let mode: EncryptionMode
    let onCompletion: (Bool) -> Void
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    @State private var enableEncryption = true
    
    var title: String {
        switch mode {
        case .setup: return "New Vault Detected"
        case .unlock: return "Encrypted Vault Detected"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.blue)
                .padding(.top)
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            if case .setup = mode {
                setupForm
            } else {
                unlockForm
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            HStack {
                Button("Cancel") {
                    onCompletion(false)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: process) {
                    if isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(confirmButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || !isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding(30)
    }
    
    var confirmButtonTitle: String {
        switch mode {
        case .setup: return enableEncryption ? "Encrypt Vault" : "Use Without Encryption"
        case .unlock: return "Unlock Vault"
        }
    }
    
    var isValid: Bool {
        switch mode {
        case .setup:
            if !enableEncryption { return true }
            return !password.isEmpty && password == confirmPassword && password.count >= 8
        case .unlock:
            return !password.isEmpty
        }
    }
    
    // MARK: - Forms
    
    var unlockForm: some View {
        VStack(alignment: .leading) {
            Text("This vault is encrypted. Enter your password to access it.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    var setupForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            Toggle("Encrypt Backups", isOn: $enableEncryption)
                .toggleStyle(.switch)
            
            if enableEncryption {
                VStack(alignment: .leading, spacing: 5) {
                    SecureField("Create Password", text: $password)
                    SecureField("Verify Password", text: $confirmPassword)
                }
                .textFieldStyle(.roundedBorder)
                
                Text("If you lose this password, your files cannot be recovered.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("Files will be stored as-is. Filenames and content will be visible to anyone with access to the drive.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Actions
    
    func process() {
        isProcessing = true
        errorMessage = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                switch mode {
                case .unlock(let identity):
                    try CryptoManager.shared.unlock(password: password, identity: identity)
                    onCompletion(true)
                    
                case .setup:
                    if enableEncryption {
                        let identity = try CryptoManager.shared.createIdentity(password: password)
                        NotificationCenter.default.post(name: .generatedNewIdentity, object: identity)
                        onCompletion(true)
                    } else {
                        CryptoManager.shared.disableEncryption()
                        let identity = VaultIdentity(vaultID: UUID())
                        NotificationCenter.default.post(name: .generatedNewIdentity, object: identity)
                        onCompletion(true)
                    }
                }
                dismiss()
            } catch {
                isProcessing = false
                if let cryptoError = error as? CryptoError, cryptoError == .invalidPassword {
                    errorMessage = "Incorrect password."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

extension Notification.Name {
    static let generatedNewIdentity = Notification.Name("anchor_generated_new_identity")
    static let openSettingsTab = Notification.Name("anchor_open_settings_tab")
}
