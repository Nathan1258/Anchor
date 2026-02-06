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
    
    @State private var newExtension = ""
    @State private var newFolder = ""
    @State private var tempS3Config = PersistenceManager.shared.s3Config
    
    @State private var isTestingConnection = false
    @State private var connectionTestMessage: String? = nil
    @State private var connectionTestSuccess: Bool = false
    
    @State private var showVaultSwitchAlert = false
    @State private var pendingVaultType: VaultType?
    @State private var pendingVaultURL: URL?
    
    @State private var showMirrorAlert = false
    @State private var pendingBackupMode: BackupMode?
    
    @State private var showPhotoVaultSwitchAlert = false
    @State private var pendingPhotoVaultType: VaultType?
    @State private var pendingPhotoVaultURL: URL?
    @State private var showPhotoImportChoice = false
    
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
            generalTab
            cloudTab
            driveTab
            photosTab
            notificationsTab
        }
        .formStyle(.grouped)
        .frame(width: 800, height: 400)
        .onChange(of: persistence.notifyBackupComplete) {
            if persistence.notifyBackupComplete {
                NotificationManager.shared.requestPermissions()
            }
        }
        .onChange(of: persistence.notifyVaultIssue) {
            if persistence.notifyVaultIssue {
                NotificationManager.shared.requestPermissions()
            }
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                Text("Automatically start Anchor when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tabItem { Label("General", systemImage: "gear") }
        .tag(0)
    }
    
    // MARK: - Cloud Tab
    private var cloudTab: some View {
        Form {
            Section(header: Text("S3 / Object Storage Credentials")) {
                TextField("Endpoint URL", text: $tempS3Config.endpoint)
                    .autocorrectionDisabled()
                TextField("Region", text: $tempS3Config.region)
                    .autocorrectionDisabled()
                TextField("Bucket Name", text: $tempS3Config.bucket)
                    .autocorrectionDisabled()
            }
            
            Section(header: Text("Authentication")) {
                TextField("Access Key ID", text: $tempS3Config.accessKey)
                    .autocorrectionDisabled()
                SecureField("Secret Access Key", text: $tempS3Config.secretKey)
                    .textContentType(.password)
            }
            
            Section {
                HStack {
                    Button("Save Credentials") {
                        persistence.s3Config = tempS3Config
                        connectionTestMessage = nil
                    }
                    .disabled(tempS3Config == persistence.s3Config)
                    
                    Spacer()
                    
                    Button(action: testConnection) {
                        if isTestingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(!tempS3Config.isValid || isTestingConnection)
                }
                
                if let message = connectionTestMessage {
                    HStack {
                        Image(systemName: connectionTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(connectionTestSuccess ? .green : .red)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(connectionTestSuccess ? .green : .red)
                    }
                }
            }
        }
        .tabItem { Label("Cloud", systemImage: "network") }
        .tag(1)
    }
    
    // MARK: - Drive Tab
    
    private var driveTab: some View {
        Form {
            Section {
                Toggle("Enable Drive Sync", isOn: $persistence.isDriveEnabled)
                    .toggleStyle(.switch)
            }
            
            Group {
                driveSourceSection
                driveDestinationSection
                driveBackupStrategySection
                driveExclusionsSection
            }
            .disabled(!persistence.isDriveEnabled)
        }
        .tabItem { Label("Drive", systemImage: "icloud.and.arrow.down") }
        .tag(2)
    }
    
    private var driveSourceSection: some View {
        Section(header: Text("Source")) {
            PathPickerRow(
                label: "Source Folder",
                path: driveWatcher.sourceURL,
                icon: "icloud",
                action: driveWatcher.selectSourceFolder
            )
        }
    }
    
    private var driveDestinationSection: some View {
        Section(header: Text("Destination")) {
            Picker("Vault Type", selection: Binding(
                get: { persistence.driveVaultType },
                set: { newValue in
                    if newValue != persistence.driveVaultType {
                        pendingVaultType = newValue
                        showVaultSwitchAlert = true
                    }
                }
            )) {
                ForEach(VaultType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if persistence.driveVaultType == .local {
                PathPickerRow(
                    label: "Local Vault Folder",
                    path: driveWatcher.vaultURL,
                    icon: "externaldrive",
                    action: {
                        driveWatcher.pickNewVaultFolder { newURL in
                            if newURL != driveWatcher.vaultURL {
                                pendingVaultURL = newURL
                                showVaultSwitchAlert = true
                            }
                        }
                    }
                )
            } else {
                S3StatusRow(config: persistence.s3Config)
            }
        }
        .alert("Switch Vault Destination?", isPresented: $showVaultSwitchAlert) {
            Button("Cancel", role: .cancel) {
                pendingVaultType = nil
                pendingVaultURL = nil
            }
            Button("Confirm & Re-scan", role: .destructive) {
                driveWatcher.applyVaultSwitch(type: pendingVaultType, url: pendingVaultURL)
                pendingVaultType = nil
                pendingVaultURL = nil
            }
        } message: {
            Text("Switching vaults requires a full re-scan to ensure all files are safe.\n\nAnchor will forget previous sync history and verify your library against the new destination.")
        }
    }
    
    private var driveBackupStrategySection: some View {
        Section(
            header: Text("Backup Strategy"),
            footer: Text(backupDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        ) {
            Picker("Mode", selection: Binding(
                get: { persistence.backupMode },
                set: { newValue in
                    if newValue == .mirror && persistence.backupMode != .mirror {
                        pendingBackupMode = newValue
                        showMirrorAlert = true
                    } else {
                        persistence.backupMode = newValue
                    }
                }
            )) {
                Text("Basic").tag(BackupMode.basic)
                Text("Mirror").tag(BackupMode.mirror)
                // Text("Snapshots").tag(BackupMode.snapshot)
            }
            .pickerStyle(.segmented)
            
            if persistence.backupMode == .snapshot {
                snapshotConfiguration
            }
        }
        .alert("Switch to Mirror Mode?", isPresented: $showMirrorAlert) {
            Button("Keep Orphans", role: .cancel) {
                if let mode = pendingBackupMode {
                    persistence.backupMode = mode
                    driveWatcher.reconcileMirrorMode(strict: false)
                }
            }
            Button("Delete from Vault", role: .destructive) {
                if let mode = pendingBackupMode {
                    persistence.backupMode = mode
                    driveWatcher.reconcileMirrorMode(strict: true)
                }
            }
        } message: {
            Text("How would you like to handle files currently in your Vault that no longer exist on your Mac?\n\n'Delete' will remove them to make the Vault an exact copy.\n'Keep' will leave them there, only mirroring future deletions.")
        }
    }
    
    private var snapshotConfiguration: some View {
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
    
    private var driveExclusionsSection: some View {
        Section(
            header: Text("Exclusions"),
            footer: Text("Anchor has default exclusions built in")
                .font(.caption)
                .foregroundColor(.secondary)
        ) {
            exclusionFileNames
            exclusionFolderNames
        }
    }
    
    private var exclusionFileNames: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ignored File Names")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
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
                Text("None")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    }
    
    private var exclusionFolderNames: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ignored Folder Names")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
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
                Text("None")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    
    // MARK: - Photos Tab
    
    private var photosTab: some View {
        Form {
            Section {
                let photosBinding = Binding<Bool>(
                    get: { persistence.isPhotosEnabled },
                    set: { newValue in
                        if newValue {
                            if persistence.loadPhotoToken() == nil {
                                showPhotoImportChoice = true
                            } else {
                                persistence.isPhotosEnabled = true
                                photoWatcher.startWatching()
                            }
                        } else {
                            // Turning OFF
                            persistence.isPhotosEnabled = false
                            photoWatcher.isRunning = false
                            photoWatcher.status = .disabled
                        }
                    }
                )
                
                Toggle("Enable Photo Backup", isOn: photosBinding)
                    .toggleStyle(.switch)
            }
            
            Group {
                Section(header: Text("Destination")) {
                    Picker("Vault Type", selection: Binding(
                        get: { persistence.photoVaultType },
                        set: { newValue in
                            if newValue != persistence.photoVaultType {
                                pendingPhotoVaultType = newValue
                                showPhotoVaultSwitchAlert = true
                            }
                        }
                    )) {
                        ForEach(VaultType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if persistence.photoVaultType == .local {
                        PathPickerRow(
                            label: "Photo Vault Folder",
                            path: photoWatcher.vaultURL,
                            icon: "photo.on.rectangle",
                            action: {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.prompt = "Select Photo Vault"
                                
                                panel.begin { response in
                                    if response == .OK, let url = panel.url {
                                        if url != photoWatcher.vaultURL {
                                            pendingPhotoVaultURL = url
                                            pendingPhotoVaultType = .local
                                            showPhotoVaultSwitchAlert = true
                                        }
                                    }
                                }
                            }
                        )
                        Text("Anchor will organize photos by Year/Month automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        S3StatusRow(config: persistence.s3Config)
                        Text("Photos will be uploaded to '\(persistence.s3Config.bucket)' in Year/Month folders.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!persistence.isPhotosEnabled)
        }
        .tabItem { Label("Photos", systemImage: "photo") }
        .tag(3)
        .alert("Switch Photo Vault?", isPresented: $showPhotoVaultSwitchAlert) {
            
            Button("Switch & Upload All") {
                if let type = pendingPhotoVaultType {
                    photoWatcher.applyVaultSwitch(type: type, url: pendingPhotoVaultURL, importHistory: true)
                }
                resetPendingState()
            }
            
            Button("Switch & Only New") {
                if let type = pendingPhotoVaultType {
                    photoWatcher.applyVaultSwitch(type: type, url: pendingPhotoVaultURL, importHistory: false)
                }
                resetPendingState()
            }
            
            Button("Cancel", role: .cancel) {
                resetPendingState()
            }
        } message: {
            Text("You are changing the backup destination. Do you want to re-upload your existing library to the new vault, or start fresh with only new photos?")
        }
        .alert("Upload Existing Photos?", isPresented: $showPhotoImportChoice) {
            Button("Only New Photos") {
                photoWatcher.markAsUpToDate()
                persistence.isPhotosEnabled = true
                photoWatcher.startWatching()
            }
            
            Button("Upload Entire Library") {
                persistence.isPhotosEnabled = true
                photoWatcher.startWatching()
            }
            
            Button("Cancel", role: .cancel) {
                persistence.isPhotosEnabled = false
            }
        } message: {
            Text("Do you want Anchor to back up all photos currently in your library, or only new photos you take from now on?")
        }
    }
    
    private func resetPendingState() {
        pendingPhotoVaultType = nil
        pendingPhotoVaultURL = nil
    }
    
    // MARK: - Notifications Tab
    
    private var notificationsTab: some View {
        Form {
            Section(header: Text("Triggers")) {
                Toggle("Notify when Backup Complete", isOn: $persistence.notifyBackupComplete)
                Toggle("Notify on Vault Issues", isOn: $persistence.notifyVaultIssue)
            }
        }
        .tabItem { Label("Notifications", systemImage: "bell.badge") }
        .tag(4)
    }
    
    private func testConnection() {
        guard tempS3Config.isValid else { return }
        
        isTestingConnection = true
        connectionTestMessage = nil
        
        Task {
            do {
                let tester = try await S3Vault.create(config: tempS3Config)
                try await tester.testConnection()
                
                DispatchQueue.main.async {
                    self.connectionTestSuccess = true
                    self.connectionTestMessage = "Connection Successful! Write access confirmed."
                    self.isTestingConnection = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.connectionTestSuccess = false
                    self.connectionTestMessage = "Connection Failed: \(error.localizedDescription)"
                    self.isTestingConnection = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

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

struct S3StatusRow: View {
    let config: S3Config
    
    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .frame(width: 20)
                .foregroundColor(config.isValid ? .green : .orange)
            
            VStack(alignment: .leading) {
                if config.isValid {
                    Text("Target Bucket: \(config.bucket)")
                        .fontWeight(.medium)
                    Text("Region: \(config.region) • Endpoint: \(config.endpoint)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("S3 Not Configured")
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                    Text("Go to the 'Cloud' tab to set up credentials.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
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
