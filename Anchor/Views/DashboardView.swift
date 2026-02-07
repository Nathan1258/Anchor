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
    
    @ObservedObject var persistence = PersistenceManager.shared
    @ObservedObject var network = NetworkMonitor.shared
    
    @Environment(\.openWindow) var openWindow
    @Namespace private var glassNamespace
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.95)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                GlassEffectContainer(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anchor")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Backup Monitor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: { openWindow(id: "settings") }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.glass)
                        .help("Open Settings")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .glassEffect()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                monitorView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    var monitorView: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    if network.status == .disconnected {
                        StatusBanner(
                            text: "No Internet Connection",
                            subtext: "Syncing paused until connection is restored.",
                            color: .red,
                            icon: "wifi.slash"
                        )
                    } else if network.status == .captivePortal {
                        StatusBanner(
                            text: "Wi-Fi Login Required",
                            subtext: "You are connected to Wi-Fi, but internet is blocked. Please log in via your browser.",
                            color: .orange,
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                    
                    if persistence.isGlobalPaused {
                        GlassEffectContainer(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Global Pause Active")
                                        .fontWeight(.semibold)
                                    if let date = persistence.pausedUntil {
                                        Text("Resuming \(date, style: .relative)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Paused indefinitely")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Button("Resume Now") {
                                    persistence.pausedUntil = nil
                                    driveWatcher.startWatching()
                                    photosWatcher.startWatching()
                                }
                                .buttonStyle(.glassProminent)
                                .controlSize(.small)
                            }
                            .padding(16)
                            .glassEffect(.regular.tint(.orange))
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
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
                            onConfigure: { 
                                NotificationCenter.default.post(name: .openSettingsTab, object: 2)
                                openWindow(id: "settings")
                            },
                            onRestore: { openWindow(id: "restore") }
                        )
                        .glassEffect(in: .rect(cornerRadius: 16))
                        
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
                            onConfigure: { 
                                NotificationCenter.default.post(name: .openSettingsTab, object: 3)
                                openWindow(id: "settings")
                            },
                            onRestore: nil
                        )
                        .glassEffect(in: .rect(cornerRadius: 16))
                    }
                    .padding(.horizontal, 20)
                }
                
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.green)
                        
                        Text(lastLogMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
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
    let onRestore: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isRunning ? statusColor.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundStyle(isRunning ? statusColor : .secondary)
                        .symbolEffect(.pulse, isActive: isRunning)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect()
                    }
                }
            }
            .padding(.top, 24)
            
            Spacer()
            
            VStack(spacing: 16) {
                MetricRow(value: primaryMetric, label: primaryLabel, isRunning: isRunning)
                MetricRow(value: secondaryMetric, label: secondaryLabel, isRunning: isRunning)
            }
            
            if isRunning && !lastActivity.isEmpty {
                VStack(spacing: 4) {
                    Text("Recent Activity")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    
                    Text(lastActivity)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                if !isConfigured {
                    Button("Configure in Settings") { onConfigure() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                } else if !isRunning {
                    Button("Start Monitor") { onStart() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Engine Running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let onRestore = onRestore, isConfigured {
                    Button(action: onRestore) {
                        Label("Browse & Restore", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricRow: View {
    let value: String
    let label: String
    let isRunning: Bool
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Spacer()
            
            Text(value)
                .font(.title2)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(isRunning ? .primary : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}

struct StatusBanner: View {
    let text: String
    let subtext: String
    let color: Color
    let icon: String
    
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                    
                    Text(subtext)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .glassEffect(.regular.tint(color))
        }
        .padding(.horizontal, 20)
    }
}
