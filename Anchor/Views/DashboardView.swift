//
//  DashboardView.swift
//  Anchor
//
//  Created by Nathan Ellis on 05/02/2026.
//
import SwiftUI

struct DashboardView: View {
    
    @EnvironmentObject var driveWatcher: DriveWatcher
    @EnvironmentObject var photosWatcher: PhotoWatcher
    @Environment(\.openWindow) var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Anchor")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("System Status: \(statusSummary)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Settings Shortcut
                Button(action: { openWindow(id: "settings") }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Open Settings")
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // MARK: - Engines
            HStack(spacing: 0) {
                
                // LEFT: Drive Engine
                EngineStatusColumn(
                    title: "iCloud Drive",
                    icon: "icloud",
                    statusColor: driveStatusColor,
                    statusText: driveWatcher.status.label,
                    isRunning: driveWatcher.isRunning,
                    isConfigured: driveWatcher.sourceURL != nil && driveWatcher.vaultURL != nil,
                    primaryMetric: "\(driveWatcher.sessionVaultedCount)",
                    primaryLabel: "Files Vaulted",
                    secondaryMetric: "\(driveWatcher.sessionScannedCount)",
                    secondaryLabel: "Scanned",
                    lastActivity: driveWatcher.lastFileProcessed,
                    onStart: driveWatcher.startWatching,
                    onConfigure: { openWindow(id: "settings") }
                )
                
                Divider()
                
                // RIGHT: Photos Engine
                EngineStatusColumn(
                    title: "Photo Library",
                    icon: "photo",
                    statusColor: photoStatusColor,
                    statusText: photosWatcher.status.label,
                    isRunning: photosWatcher.isRunning,
                    isConfigured: photosWatcher.vaultURL != nil,
                    primaryMetric: "\(photosWatcher.sessionSavedCount)",
                    primaryLabel: "Photos Saved",
                    secondaryMetric: "\(photosWatcher.totalLibraryCount)",
                    secondaryLabel: "Total Items",
                    lastActivity: photosWatcher.lastPhotoProcessed,
                    onStart: photosWatcher.startWatching,
                    onConfigure: { openWindow(id: "settings") }
                )
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // MARK: - Footer / Logs
            HStack {
                Text(lastLogMessage)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    // MARK: - Computed State
    
    var statusSummary: String {
        if driveWatcher.isRunning && photosWatcher.isRunning { return "Active" }
        if driveWatcher.isRunning || photosWatcher.isRunning { return "Partially Active" }
        return "Standby"
    }
    
    var driveStatusColor: Color {
        switch driveWatcher.status {
        case .waitingForVault: return .orange
        case .idle: return .gray
        case .active, .monitoring: return .green
        case .deleted: return .orange
        default: return .blue
        }
    }
    
    var photoStatusColor: Color {
        switch photosWatcher.status {
        case .waitingForVault: return .orange
        case .waiting, .upToDate: return .gray
        case .monitoring, .synced, .backupComplete: return .green
        case .accessDenied: return .red
        default: return .blue
        }
    }
    
    var lastLogMessage: String {
        if let dLog = driveWatcher.logs.last?.message { return "Drive: " + dLog }
        if let pLog = photosWatcher.logs.last { return "Photos: " + pLog }
        return "Ready"
    }
}

// MARK: - Subviews

struct EngineStatusColumn: View {
    let title: String
    let icon: String
    let statusColor: Color
    let statusText: String
    let isRunning: Bool
    let isConfigured: Bool
    
    let primaryMetric: String
    let primaryLabel: String
    let secondaryMetric: String
    let secondaryLabel: String
    let lastActivity: String
    
    let onStart: () -> Void
    let onConfigure: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Header
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(isRunning ? statusColor : .gray)
                    .opacity(isRunning ? 1.0 : 0.5)
                
                Text(title)
                    .font(.headline)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().stroke(Color.gray.opacity(0.3)))
            }
            .padding(.top, 30)
            
            Spacer()
            
            // Metrics
            HStack(spacing: 30) {
                MetricColumn(value: primaryMetric, label: primaryLabel)
                MetricColumn(value: secondaryMetric, label: secondaryLabel)
            }
            .opacity(isRunning ? 1.0 : 0.5)
            
            // Recent Activity
            if isRunning {
                Text(lastActivity)
                    .font(.caption2)
                    .monospaced()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            
            Spacer()
            
            // Action Button
            if !isConfigured {
                Button("Configure in Settings") { onConfigure() }
                    .buttonStyle(.bordered)
            } else if !isRunning {
                Button("Start Monitor") { onStart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Text("Engine Running")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 5)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct MetricColumn: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title)
                .fontWeight(.light)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
    }
}
