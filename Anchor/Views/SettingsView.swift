//
//  SettingsView.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import SwiftUI

struct SettingsView: View {
    
    @EnvironmentObject var driveWatcher: DriveWatcher
    @EnvironmentObject var photoWatcher: PhotoWatcher
    
    @ObservedObject var persistence = PersistenceManager.shared
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        TabView {
            // MARK: - General Tab
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                    Text("Automatically start Anchor when you log in.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tabItem { Label("General", systemImage: "gear")}
            .tag(0)
            
            // MARK: - Drive Tab
            Form {
                Section {
                    Toggle("Enable Drive Sync", isOn: $persistence.isDriveEnabled)
                        .toggleStyle(.switch)
                }
                
                Group {
                    Section(header: Text("Configuration")) {
                        PathPickerRow(
                            label: "Source Folder",
                            path: driveWatcher.sourceURL,
                            icon: "icloud",
                            action: driveWatcher.selectSourceFolder
                        )
                        
                        PathPickerRow(
                            label: "Vault Folder",
                            path: driveWatcher.vaultURL,
                            icon: "externaldrive",
                            action: driveWatcher.selectVaultFolder
                        )
                    }
                    
                    Section(header: Text("Behavior")) {
                        Toggle("Mirror Deletions", isOn: $persistence.mirrorDeletions)
                        
                        Text("If enabled, deleting a file in iCloud will delete it from the Vault immediately.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!persistence.isDriveEnabled)
            }
            .tabItem { Label("Drive", systemImage: "icloud.and.arrow.down")}
            .tag(1)
            
            // MARK: - Photos Tab
            Form {
                Section {
                    Toggle("Enable Photo Backup", isOn: $persistence.isPhotosEnabled)
                        .toggleStyle(.switch)
                }
                
                Group {
                    Section(header: Text("Backup Location")) {
                        PathPickerRow(
                            label: "Photo Vault",
                            path: photoWatcher.vaultURL,
                            icon: "photo.on.rectangle",
                            action: photoWatcher.selectVaultFolder
                        )
                        Text("Anchor will organize photos by Year/Month automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!persistence.isPhotosEnabled)
            }
            .tabItem { Label("Photos", systemImage: "photo")}
            .tag(2)
            
            // MARK: - Notifications Tab
            Form {
                Section(header: Text("Triggers")) {
                    Toggle("Notify when Backup Complete", isOn: $persistence.notifyBackupComplete)
                    Toggle("Notify on Vault Issues", isOn: $persistence.notifyVaultIssue)
                }
            }
            .tabItem { Label("Notifications", systemImage: "bell.badge") }
            .tag(3)
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 400)
        .onChange(of: persistence.notifyBackupComplete){
            if persistence.notifyBackupComplete{
                NotificationManager.shared.requestPermissions()
            }
        }
        .onChange(of: persistence.notifyVaultIssue){
            if persistence.notifyVaultIssue{
                NotificationManager.shared.requestPermissions()
            }
        }
    }
}

struct PathPickerRow: View {
    let label: String
    let path: URL?
    let icon: String
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading) {
                Text(label)
                    .fontWeight(.medium)
                if let p = path {
                    Text(p.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                } else {
                    Text("Not Set")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            Spacer()
            Button("Select...", action: action)
        }
        .padding(.vertical, 4)
    }
}
