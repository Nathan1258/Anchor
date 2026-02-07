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
    
    @State private var selectedTab: Int = 0
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
    
    @State private var showEncryptionSheet = false
    @State private var encryptionMode: EncryptionMode?
    @State private var pendingVaultProvider: VaultProvider?
    @State private var pendingVaultTypeForCheck: VaultType?
    @State private var pendingVaultURLForCheck: URL?
    
    @State private var showDriveWipeAlert = false
    @State private var showPhotosWipeAlert = false
    @State private var isWiping = false
    
    @State private var showDriveEnableAlert = false
    @State private var showPhotosEnableAlert = false
    @State private var showDesktopUnlinkAlert = false
    @State private var showDocumentsUnlinkAlert = false
    
    @State private var pendingEnableType: PendingEnableType?
    
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
        TabView(selection: $selectedTab) {
            generalTab
            cloudTab
            driveTab
            photosTab
            notificationsTab
        }
        .formStyle(.grouped)
        .frame(width: 800, height: 400)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsTab)) { notification in
            if let tabIndex = notification.object as? Int {
                selectedTab = tabIndex
            }
        }
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
        .sheet(item: $encryptionMode) { mode in
            EncryptionPasswordSheet(mode: mode) { success in
                if success {
                    finalizeVaultSetup()
                } else {
                    pendingVaultProvider = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .generatedNewIdentity)) { notification in
            if let identity = notification.object as? VaultIdentity,
               let provider = pendingVaultProvider {
                Task {
                    try? await provider.saveIdentity(identity)
                    print("✅ Identity file written to vault.")
                }
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
            
            Section(header: Text("Troubleshooting")) {
                HStack {
                    Button("Rebuild Restore Index") {
                        ReIndexManager.shared.rebuildIndex(type: persistence.driveVaultType)
                    }
                    .disabled(ReIndexManager.shared.isIndexing)
                    
                    if ReIndexManager.shared.isIndexing {
                        ProgressView().controlSize(.small)
                        Text(ReIndexManager.shared.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !ReIndexManager.shared.statusMessage.isEmpty {
                        Text(ReIndexManager.shared.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text("Use this if your Restore Browser is empty or missing files.")
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
                        verifyS3AndCheckEncryption()
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
                let driveBinding = Binding<Bool>(
                    get: { persistence.isDriveEnabled },
                    set: { newValue in
                        if newValue {
                            persistence.isDriveEnabled = true
                            driveWatcher.startWatching()
                        } else {
                            showDriveWipeAlert = true
                        }
                    }
                )
                
                Toggle("Enable Drive Sync", isOn: driveBinding)
                    .toggleStyle(.switch)
            }
            
            Group {
                driveSourceSection
                driveDestinationSection
                driveBackupStrategySection
                driveScheduleSection
                driveExclusionsSection
            }
            .disabled(!persistence.isDriveEnabled)
        }
        .tabItem { Label("Drive", systemImage: "icloud.and.arrow.down") }
        .tag(2)
        .alert("Enable Drive Sync?", isPresented: $showDriveEnableAlert) {
            Button("Cancel", role: .cancel) {}
            
            Button("Upload All") {
                enableDrive(uploadAll: true)
            }
            
            Button("Only New Files") {
                enableDrive(uploadAll: false)
            }
        } message: {
            Text("Do you want to back up all existing files in this folder, or only new files created from now on?")
        }
        .alert("Disable Drive Sync?", isPresented: $showDriveWipeAlert) {
            Button("Cancel", role: .cancel) {}
            
            Button("Keep Files") {
                disableDrive(wipe: false)
            }
            
            Button("Delete Backup", role: .destructive) {
                disableDrive(wipe: true)
            }
        } message: {
            Text("Do you want to keep the files currently in your Vault, or delete them?")
        }
        .alert("Unlink Desktop Folder?", isPresented: $showDesktopUnlinkAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Unlink") {
                unlinkDesktopFolder()
            }
        } message: {
            Text("Desktop folder will be unlinked, but your main iCloud Drive folder will continue to sync.")
        }
        .alert("Unlink Documents Folder?", isPresented: $showDocumentsUnlinkAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Unlink") {
                unlinkDocumentsFolder()
            }
        } message: {
            Text("Documents folder will be unlinked, but your main iCloud Drive folder will continue to sync.")
        }
        .disabled(isWiping)
    }
    
    private var driveSourceSection: some View {
        Section(
            header: Text("Source"),
            footer: Group {
                if let sourceURL = driveWatcher.sourceURL,
                   sourceURL.path.contains("Mobile Documents") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ℹ️ Optional: Desktop & Documents Folders")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text("These special iCloud Drive folders require separate permissions. If you want to back them up, select them below. They will be synced in addition to your main source folder.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        ) {
            PathPickerRow(
                label: "Source Folder",
                path: driveWatcher.sourceURL,
                icon: "icloud",
                action: driveWatcher.selectSourceFolder
            )
            
            // Show Desktop and Documents options if source is iCloud Drive
            if let sourceURL = driveWatcher.sourceURL,
               sourceURL.path.contains("Mobile Documents") {
                
                // Desktop folder
                HStack {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    
                    Text("Desktop (Optional)")
                    
                    Spacer()
                    
                    if driveWatcher.desktopURL != nil {
                        Text("Setup")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Button(action: { showDesktopUnlinkAlert = true }) {
                            Text("Unlink")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button("Select...", action: driveWatcher.selectDesktopFolder)
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
                
                // Documents folder
                HStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    
                    Text("Documents (Optional)")
                    
                    Spacer()
                    
                    if driveWatcher.documentsURL != nil {
                        Text("Setup")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Button(action: { showDocumentsUnlinkAlert = true }) {
                            Text("Unlink")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button("Select...", action: driveWatcher.selectDocumentsFolder)
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
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
                        pickLocalVault()
                    },
                    isEncrypted: CryptoManager.shared.isConfigured
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
    
    private var driveScheduleSection: some View {
        Section(
            header: Text("Backup Schedule"),
            footer: Text(persistence.driveScheduleMode == .realtime ? 
                        "Changes are backed up immediately when detected" : 
                        "Changes are backed up on a regular schedule")
                .font(.caption)
                .foregroundColor(.secondary)
        ) {
            Picker("Mode", selection: $persistence.driveScheduleMode) {
                Text("Realtime").tag(BackupScheduleMode.realtime)
                Text("Scheduled").tag(BackupScheduleMode.scheduled)
            }
            .pickerStyle(.segmented)
            .onChange(of: persistence.driveScheduleMode) { _, _ in
                // Restart watcher to apply new schedule
                if driveWatcher.isRunning {
                    driveWatcher.startWatching()
                }
            }
            
            if persistence.driveScheduleMode == .scheduled {
                Picker("Interval", selection: $persistence.driveScheduleInterval) {
                    ForEach(BackupScheduleInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .onChange(of: persistence.driveScheduleInterval) { _, _ in
                    // Restart watcher to apply new interval
                    if driveWatcher.isRunning {
                        driveWatcher.startWatching()
                    }
                }
            }
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
    
    private var photosScheduleSection: some View {
        Section(
            header: Text("Backup Schedule"),
            footer: Text(persistence.photosScheduleMode == .realtime ? 
                        "Changes are backed up immediately when detected" : 
                        "Changes are backed up on a regular schedule")
                .font(.caption)
                .foregroundColor(.secondary)
        ) {
            Picker("Mode", selection: $persistence.photosScheduleMode) {
                Text("Realtime").tag(BackupScheduleMode.realtime)
                Text("Scheduled").tag(BackupScheduleMode.scheduled)
            }
            .pickerStyle(.segmented)
            .onChange(of: persistence.photosScheduleMode) { _, _ in
                // Restart watcher to apply new schedule
                if photoWatcher.isRunning {
                    photoWatcher.startWatching()
                }
            }
            
            if persistence.photosScheduleMode == .scheduled {
                Picker("Interval", selection: $persistence.photosScheduleInterval) {
                    ForEach(BackupScheduleInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .onChange(of: persistence.photosScheduleInterval) { _, _ in
                    // Restart watcher to apply new interval
                    if photoWatcher.isRunning {
                        photoWatcher.startWatching()
                    }
                }
            }
        }
    }
    
    private var photosTab: some View {
        Form {
            Section {
                let photosBinding = Binding<Bool>(
                    get: { persistence.isPhotosEnabled },
                    set: { newValue in
                        if newValue {
                            attemptToEnable(type: .photos)
                        } else {
                            showPhotosWipeAlert = true
                        }
                    }
                )
                
                Toggle("Enable Photo Backup", isOn: photosBinding)
                    .toggleStyle(.switch)
            }
            .disabled(isWiping)
            
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
                            },
                            isEncrypted: CryptoManager.shared.isConfigured
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
                
                photosScheduleSection
            }
            .disabled(!persistence.isPhotosEnabled)
        }
        .tabItem { Label("Photos", systemImage: "photo") }
        .tag(3)
        .alert("Enable Photo Backup?", isPresented: $showPhotosEnableAlert) {
            Button("Cancel", role: .cancel) { }
            
            Button("Upload Entire Library") {
                enablePhotos(uploadAll: true)
            }
            
            Button("Only New Photos") {
                enablePhotos(uploadAll: false)
            }
        } message: {
            Text("Do you want Anchor to back up your entire existing library, or only new photos taken from now on?")
        }
        .alert("Disable Photo Backup?", isPresented: $showPhotosWipeAlert) {
            Button("Cancel", role: .cancel) { }
            
            Button("Keep Files") {
                disablePhotos(wipe: false)
            }
            
            Button("Delete Backup", role: .destructive) {
                disablePhotos(wipe: true)
            }
        } message: {
            Text("Do you want to keep the photos currently in your Vault, or delete them?")
        }
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
                
                SQLiteLedger.shared.resetAllFailureCounts()
                
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
    
    func verifyS3AndCheckEncryption() {
        guard tempS3Config.isValid else { return }
        
        Task {
            do {
                let provider = try await S3Vault.create(config: tempS3Config)
                
                SQLiteLedger().resetAllFailureCounts()
                
                await processVaultHandshake(provider: provider, type: .s3, url: nil)
            } catch {
                connectionTestMessage = "Failed: \(error.localizedDescription)"
            }
        }
    }
    
    func pickLocalVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select Vault"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    let provider = LocalVault(rootURL: url)
                    await processVaultHandshake(provider: provider, type: .local, url: url)
                }
            }
        }
    }
    
    // MARK: - The Handshake Logic
    
    func processVaultHandshake(provider: VaultProvider, type: VaultType, url: URL?) async {
        do {
            let identity = try await provider.loadIdentity()
            
            await MainActor.run {
                self.pendingVaultProvider = provider
                self.pendingVaultTypeForCheck = type
                self.pendingVaultURLForCheck = url
                
                if let id = identity {
                    if CryptoManager.shared.isConfigured {
                        finalizeVaultSetup()
                    } else {
                        self.encryptionMode = .unlock(id)
                        self.showEncryptionSheet = true
                    }
                } else {
                    self.encryptionMode = .setup(nil)
                    self.showEncryptionSheet = true
                }
            }
        } catch {
            print("Error checking vault identity: \(error)")
        }
    }
    
    func finalizeVaultSetup() {
        guard let type = pendingVaultTypeForCheck else { return }
        
        if type == .s3 {
            persistence.s3Config = tempS3Config
            if pendingEnableType == .drive { persistence.driveVaultType = .s3 }
            if pendingEnableType == .photos { persistence.photoVaultType = .s3 }
        } else if type == .local, let url = pendingVaultURLForCheck {
            if pendingEnableType == .drive {
                persistence.driveVaultType = .local
                driveWatcher.vaultURL = url
                persistence.saveBookmark(for: url, type: .driveVault)
            }
            if pendingEnableType == .photos {
                persistence.photoVaultType = .local
                photoWatcher.vaultURL = url
                persistence.saveBookmark(for: url, type: .photoVault)
            }
        }
        
        if pendingEnableType == .drive || pendingEnableType == nil {
            driveWatcher.applyVaultSwitch(type: type, url: pendingVaultURLForCheck)
        }
        if pendingEnableType == .photos {
            photoWatcher.applyVaultSwitch(type: type, url: pendingVaultURLForCheck, importHistory: true)
        }
        
        if let pending = pendingEnableType {
            proceedToStrategy(type: pending)
            pendingEnableType = nil
        }
        
        pendingVaultProvider = nil
        pendingVaultTypeForCheck = nil
        pendingVaultURLForCheck = nil
    }
    
    func enableDrive(uploadAll: Bool) {
        persistence.isDriveEnabled = true
        
        driveWatcher.isRunning = true
        driveWatcher.status = .active
        
        if uploadAll {
            driveWatcher.startWatching()
        } else {
            driveWatcher.markEverythingAsSynced()
        }
    }
    
    func disableDrive(wipe: Bool) {
        persistence.isDriveEnabled = false
        driveWatcher.status = .disabled
        driveWatcher.isRunning = false
        
        // Clear all Drive configuration
        driveWatcher.sourceURL?.stopAccessingSecurityScopedResource()
        driveWatcher.sourceURL = nil
        driveWatcher.vaultURL?.stopAccessingSecurityScopedResource()
        driveWatcher.vaultURL = nil
        driveWatcher.desktopURL?.stopAccessingSecurityScopedResource()
        driveWatcher.desktopURL = nil
        driveWatcher.documentsURL?.stopAccessingSecurityScopedResource()
        driveWatcher.documentsURL = nil
        
        // Clear bookmarks
        persistence.clearBookmark(type: .driveSource)
        persistence.clearBookmark(type: .driveVault)
        persistence.clearBookmark(type: .desktopFolder)
        persistence.clearBookmark(type: .documentsFolder)
        
        if wipe {
            isWiping = true
            Task {
                if let provider = try? await VaultFactory.getProvider(type: persistence.driveVaultType) {
                    let prefix = (persistence.driveVaultType == .s3) ? "drive/" : ""
                    try? await provider.wipe(prefix: prefix)
                }
                
                SQLiteLedger.shared.wipe()
                
                await MainActor.run { isWiping = false }
            }
        }
    }
    
    func enablePhotos(uploadAll: Bool) {
        persistence.isPhotosEnabled = true
        
        if uploadAll {
            photoWatcher.startWatching()
        } else {
            photoWatcher.markAsUpToDate()
            photoWatcher.startWatching()
        }
    }
    
    func disablePhotos(wipe: Bool) {
        persistence.isPhotosEnabled = false
        photoWatcher.status = .disabled
        photoWatcher.isRunning = false
        persistence.clearPhotoToken()
        
        // Clear photo vault configuration
        photoWatcher.vaultURL?.stopAccessingSecurityScopedResource()
        photoWatcher.vaultURL = nil
        
        // Clear bookmark
        persistence.clearBookmark(type: .photoVault)
        
        if wipe {
            isWiping = true
            Task {
                if let provider = try? await VaultFactory.getProvider(type: persistence.photoVaultType) {
                    let prefix = (persistence.photoVaultType == .s3) ? "photos/" : ""
                    try? await provider.wipe(prefix: prefix)
                }
                await MainActor.run { isWiping = false }
            }
        }
    }
    
    func attemptToEnable(type: PendingEnableType) {
        Task {
            let vaultType = (type == .drive) ? persistence.driveVaultType : persistence.photoVaultType
            
            guard let provider = try? await VaultFactory.getProvider(type: vaultType) else {
                // show an error alert here.
                return
            }
            
            await MainActor.run {
                self.pendingEnableType = type
                Task { await processVaultHandshake(provider: provider, type: vaultType, url: nil) }
            }
        }
    }
    
    func proceedToStrategy(type: PendingEnableType) {
        if type == .drive {
            showDriveEnableAlert = true
        } else {
            if persistence.loadPhotoToken() == nil {
                showPhotosEnableAlert = true
            } else {
                enablePhotos(uploadAll: true)
            }
        }
    }
    
    func unlinkDesktopFolder() {
        driveWatcher.desktopURL?.stopAccessingSecurityScopedResource()
        driveWatcher.desktopURL = nil
        persistence.clearBookmark(type: .desktopFolder)
    }
    
    func unlinkDocumentsFolder() {
        driveWatcher.documentsURL?.stopAccessingSecurityScopedResource()
        driveWatcher.documentsURL = nil
        persistence.clearBookmark(type: .documentsFolder)
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
        var isEncrypted: Bool = false
        
        var body: some View {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading) {
                    Text(label)
                        .fontWeight(.medium)
                    if let p = path {
                        Text("\(p.path) \(isEncrypted ? " - Encryption Enabled" : "")")
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
}
