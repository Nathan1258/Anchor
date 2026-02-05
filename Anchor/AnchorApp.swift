//
//  AnchorApp.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//

import SwiftUI

@main
struct AnchorApp: App {
    
    @StateObject private var driveWatcher = DriveWatcher()
    @StateObject private var photosWatcher = PhotoWatcher()
    
    @ObservedObject var persistence = PersistenceManager.shared
    
    var body: some Scene {
        MenuBarExtra{
            Main()
                .environmentObject(driveWatcher)
                .environmentObject(photosWatcher)
        } label: {
            Label {
                Text("Anchor")
            } icon: {
                if persistence.isGlobalPaused{
                    Image(systemName: "pause.circle")
                }else{
                    let image: NSImage = {
                        let ratio = $0.size.height / $0.size.width
                        $0.size.height = 32
                        $0.size.width = 32 / ratio
                        return $0
                    }(NSImage(named: "MenuBarIcon")!)
                    
                    Image(nsImage: image)
                }
            }
        }
        
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
    }
}

struct Main: View {
    
    @EnvironmentObject var driveWatcher: DriveWatcher
    @EnvironmentObject var photosWatcher: PhotoWatcher
    @ObservedObject var persistence = PersistenceManager.shared
    
    @Environment(\.openWindow) var openWindow
    
    var statusText: String {
        if persistence.isGlobalPaused {
            return "⛔️ Global Pause Active"
        }
        
        switch photosWatcher.status {
        case .scanning: return "Photos: Scanning Library..."
        case .processing(let current, let total): return "Photos: Processing \(current)/\(total)..."
        case .checkingForChanges: return "Photos: Checking changes..."
        case .synced(let count): return "Photos: Synced \(count) items"
        default: break
        }
        
        switch driveWatcher.status {
        case .scanning: return "Drive: Smart Scanning..."
        case .downloading(let filename): return "Drive: Downloading \(filename)..."
        case .vaulted(let filename): return "Drive: Vaulted \(filename)"
        case .deleted(let filename): return "Drive: Deleted \(filename)"
        case .newItem: return "Drive: New Item Detected"
        default: break
        }
        
        if driveWatcher.status == .active || driveWatcher.status == .monitoring {
            return "Anchor is Active"
        }
        
        return "Idle"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            HStack {
                Circle()
                    .fill(statusText == "Idle" ? Color.gray : Color.green)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
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
                    
                } else {
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
                        HStack {
                            Image(systemName: "pause.circle")
                            Text("Pause Syncing")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.vertical, 4)
                }
                
                Divider()
                MenuButton(title: "Open Anchor", icon: "macwindow") {
                    openWindow(id: "dashboard")
                }
                
                MenuButton(title: "Settings...", icon: "gear") {
                    openWindow(id: "settings")
                }
                
                Divider()
                
                MenuButton(title: "Quit Anchor", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(width: 300)
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
}
