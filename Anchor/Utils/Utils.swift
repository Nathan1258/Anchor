//
//  Utils.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation

func performWithActivity<T>(_ reason: String, block: () async throws -> T) async rethrows -> T {
    let options: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
    
    let activity = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
    defer {
        ProcessInfo.processInfo.endActivity(activity)
    }
    
    return try await block()
}
