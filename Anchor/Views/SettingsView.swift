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
    @ObservedObject var exclusionManager = ExclusionManager.shared
    
    @State private var newExtension: String = ""
    @State private var newFolder: String = ""
    
    var backupDescription: String {
        switch persistence.backupMode {
        case .basic:
            return "Deleted files on iCloud will remain untouched in your vault."
        case .mirror:
            return "iCloud Drive and your vault are synced exactly. Deleting a file in iCloud deletes it from the Vault immediately."
        case .snapshot:
            return "Creates a timeline of your files. You can browse past versions of folders even if files were modified or deleted."
        }
    }
    
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
                    
                    Section(
                        header: Text("Backup Strategy"),
                        footer: Text(backupDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    ) {
                        Picker("Mode", selection: $persistence.backupMode) {
                            Text("Basic").tag(BackupMode.basic)
                            Text("Mirror").tag(BackupMode.mirror)
//                            Text("Snapshots").tag(BackupMode.snapshot)
                        }
                        .pickerStyle(.segmented)
                        
                        if persistence.backupMode == .snapshot {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text("Time Machine Style")
                                            .font(.headline)
                                        Text("Creates browsable history folders using space-saving hard links.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                Divider()
                                
                                Picker("Snapshot Frequency", selection: $persistence.snapshotFrequency) {
                                    Text("Every 15 Minutes").tag(15)
                                    Text("Hourly").tag(60)
                                    Text("Daily").tag(1440)
                                }
                                
                                Toggle("Auto-Prune Old Snapshots", isOn: $persistence.autoPrune)
                                if persistence.autoPrune {
                                    Text("Keeps hourly backups for 24h, daily for a month, then weekly.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onChange(of: persistence.backupMode){ oldValue, newValue in
                        if newValue == BackupMode.mirror{
                            // Show alert asking if the user wants to delete files already deleted in iCloud or not
                        }
                    }
                    
                    Section(
                        header: Text("Exclusions"),
                        footer:
                            Text("Anchor has default exclusions built in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    ){
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ignored File Names").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            if !exclusionManager.userIgnoredExtensions.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(exclusionManager.userIgnoredExtensions, id: \.self) { ext in
                                            ExclusionToken(label: ".\(ext)") {
                                                exclusionManager.removeExtension(ext)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 26)
                            } else {
                                Text("None").font(.caption).foregroundColor(.secondary)
                            }
                            
                            HStack {
                                TextField("Add extension (e.g. log, tmp)", text: $newExtension)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        exclusionManager.addExtension(newExtension)
                                        newExtension = ""
                                    }
                                Button {
                                    exclusionManager.addExtension(newExtension)
                                    newExtension = ""
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .disabled(newExtension.isEmpty)
                            }
                            
                        }
                        .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ignored Folder Names").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                            if !exclusionManager.userIgnoredFolderNames.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(exclusionManager.userIgnoredFolderNames, id: \.self) { name in
                                            ExclusionToken(label: name) {
                                                exclusionManager.removeFolder(name)
                                            }
                                        }
                                    }
                                }
                                .frame(height: 26)
                            } else {
                                Text("None").font(.caption).foregroundColor(.secondary)
                            }
                            
                            HStack {
                                TextField("Add folder name (e.g. build)", text: $newFolder)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        exclusionManager.addFolder(newFolder)
                                        newFolder = ""
                                    }
                                Button {
                                    exclusionManager.addFolder(newFolder)
                                    newFolder = ""
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .disabled(newFolder.isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
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

struct ExclusionToken: View {
    let label: String
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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
