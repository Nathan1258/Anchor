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
    
    var body: some Scene {
        MenuBarExtra{
            Main()
                .environmentObject(driveWatcher)
                .environmentObject(photosWatcher)
        } label: {
            Label {
                Text("Anchor")
            } icon: {
                let image: NSImage = {
                    let ratio = $0.size.height / $0.size.width
                    $0.size.height = 32
                    $0.size.width = 32 / ratio
                    return $0
                }(NSImage(named: "MenuBarIcon")!)
                
                Image(nsImage: image)
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
    
    @Environment(\.openWindow) var openWindow
    
    var statusText: String {
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
}
