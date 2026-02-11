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
    @ObservedObject var integrityManager = IntegrityManager.shared
    
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
            
            monitorView
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
                    
                    if persistence.isDriveEnabled && driveWatcher.status == .waitingForVault {
                        StatusBanner(
                            text: "Drive Vault Folder Not Found",
                            subtext: "The destination vault folder is disconnected, moved, or deleted. Backup will resume when the folder is available again.",
                            color: .red,
                            icon: "externaldrive.badge.exclamationmark"
                        )
                    }
                    
                    if persistence.isDriveEnabled && driveWatcher.status == .disabled {
                        StatusBanner(
                            text: "Drive Backup Disabled",
                            subtext: "Could not initialize vault. Check settings and ensure vault folder is accessible.",
                            color: .red,
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                    
                    if persistence.isPhotosEnabled && photosWatcher.status == .waitingForVault {
                        StatusBanner(
                            text: "Photos Vault Folder Not Found",
                            subtext: "The destination vault folder is disconnected, moved, or deleted. Backup will resume when the folder is available again.",
                            color: .red,
                            icon: "externaldrive.badge.exclamationmark"
                        )
                    }
                    
                    if persistence.isPhotosEnabled && photosWatcher.status == .disabled {
                        StatusBanner(
                            text: "Photos Backup Disabled",
                            subtext: "Could not initialize vault. Check settings and ensure vault folder is accessible.",
                            color: .red,
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
                
                GlassEffectContainer(spacing: 16) {
                    IntegrityStatusCard(
                        filesVerified: integrityManager.filesVerified,
                        filesPending: integrityManager.filesPending,
                        filesWithErrors: integrityManager.filesWithErrors,
                        totalFiles: integrityManager.totalFiles,
                        isVerifying: integrityManager.isVerifying,
                        onVerifyNow: {
                            integrityManager.verifyNow()
                        }
                    )
                    .glassEffect(in: .rect(cornerRadius: 16))
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
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isRunning ? statusColor.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(isRunning ? statusColor : .secondary)
                        .symbolEffect(.pulse, isActive: isRunning)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            HStack(spacing: 12) {
                MetricRow(value: primaryMetric, label: primaryLabel, isRunning: isRunning)
                MetricRow(value: secondaryMetric, label: secondaryLabel, isRunning: isRunning)
            }
            .padding(.horizontal, 12)
            
            if isRunning && !lastActivity.isEmpty {
                Text(lastActivity)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            
            Spacer()
            
            VStack(spacing: 6) {
                if !isConfigured {
                    Button("Configure in Settings") { onConfigure() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                } else if !isRunning {
                    Button("Start Monitor") { onStart() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let onRestore = onRestore, isConfigured {
                    Button(action: onRestore) {
                        Label("Browse & Restore", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.mini)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 320)
    }
}

struct MetricRow: View {
    let value: String
    let label: String
    let isRunning: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(isRunning ? .primary : .secondary)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
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

struct IntegrityStatusCard: View {
    let filesVerified: Int
    let filesPending: Int
    let filesWithErrors: Int
    let totalFiles: Int
    let isVerifying: Bool
    let onVerifyNow: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(integrityColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backup Integrity")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: onVerifyNow) {
                    HStack(spacing: 4) {
                        if isVerifying {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isVerifying ? "Verifying..." : "Verify Now")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isVerifying)
            }
            
            Divider()
            
            HStack(spacing: 16) {
                StatColumn(
                    value: "\(filesVerified)",
                    label: "Verified",
                    color: .green,
                    icon: "checkmark.circle.fill"
                )
                
                StatColumn(
                    value: "\(filesPending)",
                    label: "Pending",
                    color: .orange,
                    icon: "clock.fill"
                )
                
                StatColumn(
                    value: "\(filesWithErrors)",
                    label: "Errors",
                    color: filesWithErrors > 0 ? .red : .secondary,
                    icon: "exclamationmark.triangle.fill"
                )
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(totalFiles)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Text("Total Files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
    
    var integrityColor: Color {
        if filesWithErrors > 0 {
            return .red
        } else if filesPending > filesVerified {
            return .orange
        } else {
            return .green
        }
    }
    
    var statusText: String {
        if isVerifying {
            return "Verification in progress..."
        } else if filesWithErrors > 0 {
            return "Issues detected - review required"
        } else if filesPending > 0 {
            return "\(filesPending) files awaiting verification"
        } else if totalFiles > 0 {
            return "All files verified"
        } else {
            return "No files to verify"
        }
    }
}

struct StatColumn: View {
    let value: String
    let label: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
