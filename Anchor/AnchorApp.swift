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
    }
}

struct Main: View {
    
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                MenuButton(title: "Open Anchor", icon: "macwindow") {
                    print("Open Window")
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
        .frame(width: 300, height: 180)
    }
}
