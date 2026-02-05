//
//  LogEntry.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let message: String
    let timestamp = Date()
}
