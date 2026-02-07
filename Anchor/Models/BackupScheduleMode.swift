//
//  BackupScheduleMode.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//

import Foundation

enum BackupScheduleMode: Int, CaseIterable, Identifiable {
    case realtime = 0
    case scheduled = 1
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .realtime: return "Realtime"
        case .scheduled: return "Scheduled"
        }
    }
    
    var description: String {
        switch self {
        case .realtime:
            return "Backs up immediately when changes are detected"
        case .scheduled:
            return "Backs up on a regular schedule"
        }
    }
}

enum BackupScheduleInterval: Int, CaseIterable, Identifiable {
    case every15Minutes = 15
    case every30Minutes = 30
    case hourly = 60
    case every2Hours = 120
    case every4Hours = 240
    case every6Hours = 360
    case every12Hours = 720
    case daily = 1440
    
    var id: Int { rawValue }
    
    var label: String {
        switch self {
        case .every15Minutes: return "Every 15 Minutes"
        case .every30Minutes: return "Every 30 Minutes"
        case .hourly: return "Hourly"
        case .every2Hours: return "Every 2 Hours"
        case .every4Hours: return "Every 4 Hours"
        case .every6Hours: return "Every 6 Hours"
        case .every12Hours: return "Every 12 Hours"
        case .daily: return "Daily"
        }
    }
}
