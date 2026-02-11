//
//  EnergyManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 11/02/2026.
//

import Foundation
import Combine
import IOKit.pwr_mgt

@MainActor
class EnergyManager: ObservableObject {
    static let shared = EnergyManager()
    
    @Published private(set) var isSleepPrevented = false
    private var assertionID: IOPMAssertionID = 0
    private var activeBackupCount = 0
    
    private init() {}
    
    func beginBackup() {
        activeBackupCount += 1
        
        guard SettingsManager.shared.preventSleepWhileBackingUp else { return }
        
        if !isSleepPrevented {
            preventSleep()
        }
    }
    
    func endBackup() {
        activeBackupCount = max(0, activeBackupCount - 1)
        
        if activeBackupCount == 0 && isSleepPrevented {
            allowSleep()
        }
    }
    
    private func preventSleep() {
        let reason = "Anchor backup in progress" as CFString
        let assertionType = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        
        let success = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        
        if success == kIOReturnSuccess {
            isSleepPrevented = true
            print("✅ Sleep prevention enabled (Assertion ID: \(assertionID))")
        } else {
            print("⚠️ Failed to prevent sleep: \(success)")
        }
    }
    
    private func allowSleep() {
        guard isSleepPrevented else { return }
        
        let success = IOPMAssertionRelease(assertionID)
        
        if success == kIOReturnSuccess {
            isSleepPrevented = false
            assertionID = 0
            print("✅ Sleep prevention disabled")
        } else {
            print("⚠️ Failed to release sleep assertion: \(success)")
        }
    }
    
    nonisolated deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
