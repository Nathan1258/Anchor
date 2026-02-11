//
//  SettingsManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Combine
import SwiftUI
import ServiceManagement

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("launchAtLogin") var launchAtLogin = false {
        didSet {
            updateLaunchAtLogin()
        }
    }
    
    @AppStorage("preventSleepWhileBackingUp") var preventSleepWhileBackingUp = true
        
    private func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
}
