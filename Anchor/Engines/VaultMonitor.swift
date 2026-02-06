//
//  VaultMonitor.swift
//  Anchor
//
//  Created by Nathan Ellis on 05/02/2026.
//
import Foundation
import AppKit

class VaultMonitor {
    
    private let vaultURL: URL
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.anchor.vaultMonitor", qos: .utility)
    
    var onDisconnect: (() -> Void)?
    var onReconnect: (() -> Void)?
    
    private var isConnected: Bool = true
    
    init(url: URL) {
        self.vaultURL = url
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeDidChange),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeDidChange),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
    }
    
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        checkHealth()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    @objc private func volumeDidChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkHealth()
        }
    }
    
    private func checkHealth() {
        queue.async {
            let pathExists = FileManager.default.fileExists(atPath: self.vaultURL.path)
            let isInTrash = self.vaultURL.pathComponents.contains(".Trash") ||
            self.vaultURL.pathComponents.contains("Trash")
            
            DispatchQueue.main.async {
                if (pathExists && !isInTrash) && !self.isConnected {
                    self.isConnected = true
                    print("🔌 Vault Reconnected: \(self.vaultURL.lastPathComponent)")
                    self.onReconnect?()
                    
                } else if (!pathExists || isInTrash) && self.isConnected {
                    self.isConnected = false
                    print("🔌 Vault Disconnected: \(self.vaultURL.lastPathComponent)")
                    self.onDisconnect?()
                }
            }
        }
    }
    
    deinit {
        stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
