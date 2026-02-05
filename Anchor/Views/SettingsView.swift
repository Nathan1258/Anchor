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
    
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var mirrorDeletions = PersistenceManager.shared.mirrorDeletions
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $settings.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.body)
                        Text("Automatically start Anchor when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle())
            }
            .padding()
            
            Toggle(isOn: $mirrorDeletions) {
                VStack(alignment: .leading) {
                    Text("Mirror Deletions")
                    Text("If enabled, deleting a file in iCloud will delete it from the Vault.")
                        .font(.caption)
                        .foregroundColor(mirrorDeletions ? .red : .secondary)
                }
            }
            .onChange(of: mirrorDeletions) { PersistenceManager.shared.mirrorDeletions = mirrorDeletions }
            .padding()
            
            Divider()
            
            // MARK: - Anchor Safety Net Controls
            VStack(alignment: .leading, spacing: 12) {
                Text("Safety Net Configuration")
                    .font(.headline)
                
                // Source Selector
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Source (iCloud)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(driveWatcher.sourceURL?.lastPathComponent ?? "Select Folder...")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Select") {
                        driveWatcher.selectSourceFolder()
                    }
                }
                
                // Vault Selector
                HStack {
                    Image(systemName: "externaldrive")
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Vault (Local)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(driveWatcher.vaultURL?.lastPathComponent ?? "Select Folder...")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Select") {
                        driveWatcher.selectVaultFolder()
                    }
                }
                
                Divider()
                
                // Action Button
                Button(action: {
                    driveWatcher.startWatching()
                }) {
                    HStack {
                        Circle()
                            .fill(driveWatcher.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(driveWatcher.isRunning ? "Watching for changes..." : "Start Watcher")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(driveWatcher.sourceURL == nil || driveWatcher.vaultURL == nil)
                .controlSize(.large)
                
                // Live Logs (For Testing)
                GroupBox(label: Text("Live Logs").font(.caption)) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(driveWatcher.logs) { entry in
                                HStack(alignment: .top) {
                                    Text(entry.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text(entry.message)
                                        .font(.system(size: 10, design: .monospaced))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if driveWatcher.logs.isEmpty {
                                Text("Ready to start.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(4)
                    }
                }
                .frame(height: 80)
            }
            .padding()
            
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Photos Vacuum")
                    .font(.headline)

                HStack {
                    Image(systemName: "photo.on.rectangle")
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Photo Vault")
                            .font(.caption).foregroundColor(.secondary)
                        Text(photoWatcher.vaultURL?.path ?? "Select Folder...")
                            .font(.system(size: 11))
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Select") { photoWatcher.selectVaultFolder() }
                }
                
                Button(action: { photoWatcher.startWatching() }) {
                    HStack {
                        Circle().fill(photoWatcher.isRunning ? Color.green : Color.gray).frame(width: 8, height: 8)
                        Text(photoWatcher.isRunning ? "Scanning & Watching..." : "Start Vacuum")
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Logs for Photos
                GroupBox(label: Text("Photo Logs").font(.caption)) {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(photoWatcher.logs, id: \.self) { log in
                                Text(log).font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                }
                .frame(height: 80)
            }
            .padding()
            
            Spacer()
        }
        .frame(width: 320, height: 600)
    }
}

#Preview {
    SettingsView()
}
