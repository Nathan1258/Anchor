//
//  AnchorApp.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []
    
    var driveWatcher: DriveWatcher?
    var photoWatcher: PhotoWatcher?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupWindowObservers()
        IntegrityManager.shared.startVerification()
        
        Task { @MainActor in
            if PersistenceManager.shared.metricsServerEnabled {
                MetricsServer.shared.port = UInt16(PersistenceManager.shared.metricsServerPort)
                MetricsServer.shared.start()
            }
        }
    }
    
    func setWatchers(drive: DriveWatcher, photo: PhotoWatcher) {
        self.driveWatcher = drive
        self.photoWatcher = photo
        
        Task { @MainActor in
            MetricsServer.shared.driveWatcher = drive
            MetricsServer.shared.photoWatcher = photo
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        SQLiteLedger.shared.performCheckpoint()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        
        Task { @MainActor in
            MetricsServer.shared.stop()
        }
    }
    
    private func setupWindowObservers() {
        let didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActivationPolicy()
        }
        
        let willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateActivationPolicy()
            }
        }
        
        windowObservers = [didBecomeKeyObserver, willCloseObserver]
    }
    
    private func updateActivationPolicy() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible &&
            (window.title == "Settings" || window.title == "Dashboard" || window.title == "Restore Browser")
        }
        
        let newPolicy: NSApplication.ActivationPolicy = hasVisibleWindows ? .regular : .accessory
        
        if NSApp.activationPolicy() != newPolicy {
            NSApp.setActivationPolicy(newPolicy)
            
            if newPolicy == .regular {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

@main
struct AnchorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var driveWatcher = DriveWatcher()
    @StateObject private var photosWatcher = PhotoWatcher()
    
    @ObservedObject var persistence = PersistenceManager.shared
    
    var body: some Scene {
        MenuBarExtra{
            Main()
                .environmentObject(driveWatcher)
                .environmentObject(photosWatcher)
                .onAppear {
                    appDelegate.setWatchers(drive: driveWatcher, photo: photosWatcher)
                }
        } label: {
            Label {
                Text("Anchor")
            } icon: {
                if persistence.isGlobalPaused{
                    Image(systemName: "pause.circle")
                }else{
                    Image(nsImage: createMenuBarIcon())
                }
            }
        }
        .menuBarExtraStyle(.window)
        
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(driveWatcher)
                .environmentObject(photosWatcher)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("Dashboard", id: "dashboard"){
            DashboardView()
                .environmentObject(driveWatcher)
                .environmentObject(photosWatcher)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        Window("Restore Browser", id: "restore") {
            RestoreBrowserView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
    
    private func getMenuBarStatusColor() -> NSColor {
        if !persistence.isDriveEnabled && !persistence.isPhotosEnabled {
            return .systemGray
        }
        
        if driveWatcher.status == .waitingForVault || photosWatcher.status == .waitingForVault {
            return .systemRed
        }
        
        if driveWatcher.status == .disabled || photosWatcher.status == .disabled {
            return .systemRed
        }
        
        if driveWatcher.status == .scanning || photosWatcher.status == .scanning {
            return .systemBlue
        }
        
        if driveWatcher.isRunning || photosWatcher.isRunning {
            return .systemGreen
        }
        
        return .systemGray
    }
    
    private func createMenuBarIcon() -> NSImage {
        guard let baseImage = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)!
        }
        
        let ratio = baseImage.size.height / baseImage.size.width
        let targetHeight: CGFloat = 22
        let targetWidth = targetHeight / ratio
        
        let finalSize = NSSize(width: targetWidth, height: targetHeight)
        let finalImage = NSImage(size: finalSize)
        
        finalImage.lockFocus()
        
        baseImage.draw(in: NSRect(origin: .zero, size: finalSize))
        
        let statusColor = getMenuBarStatusColor()
        let dotSize: CGFloat = 6
        let dotRect = NSRect(
            x: finalSize.width - dotSize - 1,
            y: finalSize.height - dotSize - 1,
            width: dotSize,
            height: dotSize
        )
        
        let path = NSBezierPath(ovalIn: dotRect)
        statusColor.setFill()
        path.fill()
        
        NSColor.black.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        
        finalImage.unlockFocus()
        finalImage.isTemplate = false
        
        return finalImage
    }
    
}

struct VaultStatusChecker {
    static func checkOnStartup(driveWatcher: DriveWatcher, photoWatcher: PhotoWatcher) {
        NotificationManager.shared.requestPermissions()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let persistence = PersistenceManager.shared
            var issues: [String] = []
            
            if persistence.isDriveEnabled {
                if driveWatcher.status == .waitingForVault {
                    issues.append("Drive vault folder is missing or disconnected")
                } else if driveWatcher.status == .disabled {
                    issues.append("Drive backup could not start - check vault configuration")
                }
            }
            
            if persistence.isPhotosEnabled {
                if photoWatcher.status == .waitingForVault {
                    issues.append("Photos vault folder is missing or disconnected")
                } else if photoWatcher.status == .disabled {
                    issues.append("Photos backup could not start - check vault configuration")
                }
            }
            
            if !issues.isEmpty {
                let title = issues.count == 1 ? "Vault Issue Detected" : "Multiple Vault Issues Detected"
                let body = issues.joined(separator: "\n")
                NotificationManager.shared.send(title: title, body: body, type: .vaultIssue)
            }
        }
    }
    
    static func isVaultInTrash(_ url: URL) -> Bool {
        let username = NSUserName()
        let userTrashPath = "/Users/\(username)/.Trash"
        return url.path.hasPrefix(userTrashPath)
    }
}

struct Main: View {
    
    @EnvironmentObject var driveWatcher: DriveWatcher
    @EnvironmentObject var photosWatcher: PhotoWatcher
    @ObservedObject var persistence = PersistenceManager.shared
    
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismiss) var dismiss
    
    var statusInfo: (text: String, color: Color, isActive: Bool) {
        if persistence.isGlobalPaused {
            return ("Paused", .orange, false)
        }
        
        switch photosWatcher.status {
        case .scanning: return ("Scanning Photos", .blue, true)
        case .processing(let current, let total): return ("Processing \(current)/\(total)", .blue, true)
        case .checkingForChanges: return ("Checking Photos", .blue, true)
        case .synced(let count) where count > 0: return ("\(count) Photo\(count == 1 ? "" : "s") Synced", .green, false)
        default: break
        }
        
        switch driveWatcher.status {
        case .scanning: return ("Scanning Drive", .blue, true)
        case .downloading(let filename): return ("Downloading \(filename)", .blue, true)
        case .vaulted(let filename): return ("Backed up \(filename)", .green, true)
        case .deleted(let filename): return ("Deleted \(filename)", .orange, true)
        case .newItem: return ("New Item Detected", .blue, true)
        case .active, .monitoring: return ("Monitoring", .green, true)
        case .disabled: return ("Disabled", .gray, false)
        case .paused: return ("Paused", .orange, false)
        case .waitingForVault: return ("Waiting for Vault", .orange, false)
        default: break
        }
        
        return ("Idle", .gray, false)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusInfo.color)
                        .frame(width: 8, height: 8)
                    
                    Text(statusInfo.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !persistence.isGlobalPaused && (persistence.isDriveEnabled || persistence.isPhotosEnabled) {
                        Menu {
                            Button("Pause for 1 Hour") {
                                pause(hours: 1)
                            }
                            Button("Pause for 2 Hours") {
                                pause(hours: 2)
                            }
                            Button("Pause Until Tomorrow") {
                                pauseUntilTomorrow()
                            }
                        } label: {
                            Image(systemName: "pause.circle")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
                }
                
                HStack(spacing: 4) {
                    if persistence.isDriveEnabled {
                        StatusBadge(icon: "icloud", label: "Drive", isActive: driveWatcher.isRunning)
                    }
                    if persistence.isPhotosEnabled {
                        StatusBadge(icon: "photo", label: "Photos", isActive: photosWatcher.isRunning)
                    }
                    if !persistence.isDriveEnabled && !persistence.isPhotosEnabled {
                        Text("No services enabled")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            VStack(spacing: 0) {
                if persistence.isGlobalPaused {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.orange)
                            Text("Syncing Paused")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        if let date = persistence.pausedUntil {
                            Text("Resuming \(date, style: .relative)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        
                        Button(action: { persistence.pausedUntil = nil }) {
                            Text("Resume Now")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                }
                
                Divider()
                MenuButton(title: "Open Anchor", icon: "macwindow") {
                    openOrFocusWindow(id: "dashboard", title: "Dashboard")
                }
                
                MenuButton(title: "Settings...", icon: "gear") {
                    openOrFocusWindow(id: "settings", title: "Settings")
                }
                
                Divider()
                
                MenuButton(title: "Quit Anchor", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(width: 300)
        .onAppear {
            VaultStatusChecker.checkOnStartup(driveWatcher: driveWatcher, photoWatcher: photosWatcher)
        }
    }
    
    func pause(hours: Double) {
        persistence.pausedUntil = Date().addingTimeInterval(hours * 3600)
    }
    
    func pauseUntilTomorrow() {
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()),
           let nextMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            persistence.pausedUntil = nextMorning
        }
    }
    
    func openOrFocusWindow(id: String, title: String) {
        if let existingWindow = NSApp.windows.first(where: { $0.title == title && $0.isVisible }) {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: id)
        }
        
        dismiss()
    }
}

struct StatusBadge: View {
    let icon: String
    let label: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isActive ? .white : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.2))
        )
    }
}


