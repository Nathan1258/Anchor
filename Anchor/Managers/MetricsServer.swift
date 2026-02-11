//
//  MetricsServer.swift
//  Anchor
//
//  Created by Nathan Ellis on 11/02/2026.
//

import Foundation
import Combine
import Network

struct MetricsResponse: Codable {
    let status: String
    let lastSuccessfulBackup: Int64?
    let filesPending: Int
    let integrityHealth: String
    let driveStatus: String
    let photosStatus: String
    let filesVaulted: Int
    let photosBackedUp: Int
    let integrityVerified: Int
    let integrityErrors: Int
    let networkStatus: String
    let isPaused: Bool
    let hostname: String
    let appVersion: String
    let timestamp: Int64
}

@MainActor
class MetricsServer: ObservableObject {
    static let shared = MetricsServer()
    
    @Published var isRunning = false
    @Published var port: UInt16 = 9099
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    
    weak var driveWatcher: AnyObject?
    weak var photoWatcher: AnyObject?
    
    private init() {}
    
    func start() {
        guard !isRunning else { return }
        
        let port = NWEndpoint.Port(rawValue: self.port) ?? NWEndpoint.Port(integerLiteral: 9099)
        let serverPort = self.port
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: port)
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        print("Metrics server started on port \(serverPort)")
                    case .failed(let error):
                        print("Metrics server failed: \(error)")
                        self.isRunning = false
                    case .cancelled:
                        self.isRunning = false
                        print("Metrics server stopped")
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .main)
        } catch {
            print("Failed to start metrics server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        
        for connection in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        isRunning = false
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, context, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let data = data, !data.isEmpty {
                    self.handleRequest(data: data, connection: connection)
                }
                
                if isComplete || error != nil {
                    connection.cancel()
                    self.connections.removeAll { $0 === connection }
                }
            }
        }
    }
    
    private func handleRequest(data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let method = components[0]
        let path = components[1]
        
        if method == "GET" && path == "/metrics" {
            handleMetricsRequest(connection: connection)
        } else if method == "GET" && path == "/" {
            handleRootRequest(connection: connection)
        } else {
            sendResponse(connection: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    private func handleMetricsRequest(connection: NWConnection) {
        let metrics = collectMetrics()
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(metrics)
            
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                sendResponse(connection: connection, statusCode: 200, body: jsonString, contentType: "application/json")
            } else {
                sendResponse(connection: connection, statusCode: 500, body: "Internal Server Error")
            }
        } catch {
            print("Failed to encode metrics: \(error)")
            sendResponse(connection: connection, statusCode: 500, body: "Internal Server Error")
        }
    }
    
    private func handleRootRequest(connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Anchor Metrics</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; }
                h1 { color: #007AFF; }
                a { color: #007AFF; text-decoration: none; }
                a:hover { text-decoration: underline; }
            </style>
        </head>
        <body>
            <h1>Anchor Backup Metrics</h1>
            <p>Metrics endpoint: <a href="/metrics">/metrics</a></p>
            <p>This server provides backup status metrics for Grafana, Home Assistant, and other monitoring tools.</p>
        </body>
        </html>
        """
        sendResponse(connection: connection, statusCode: 200, body: html, contentType: "text/html")
    }
    
    private func collectMetrics() -> MetricsResponse {
        let persistence = PersistenceManager.shared
        let integrityManager = IntegrityManager.shared
        let networkMonitor = NetworkMonitor.shared
        
        guard let driveWatcher = driveWatcher as? DriveWatcher,
              let photoWatcher = photoWatcher as? PhotoWatcher else {
            return MetricsResponse(
                status: "idle",
                lastSuccessfulBackup: nil,
                filesPending: 0,
                integrityHealth: "100%",
                driveStatus: "Unknown",
                photosStatus: "Unknown",
                filesVaulted: 0,
                photosBackedUp: 0,
                integrityVerified: 0,
                integrityErrors: 0,
                networkStatus: "unknown",
                isPaused: false,
                hostname: Host.current().localizedName ?? "Unknown",
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
                timestamp: Int64(Date().timeIntervalSince1970)
            )
        }
        
        let status: String
        if persistence.isGlobalPaused {
            status = "paused"
        } else if driveWatcher.isRunning || photoWatcher.isRunning {
            status = "running"
        } else {
            status = "idle"
        }
        
        let lastBackup: Int64? = nil
        
        let integrityHealth: String
        if integrityManager.totalFiles > 0 {
            let percentage = (Double(integrityManager.filesVerified) / Double(integrityManager.totalFiles)) * 100
            integrityHealth = String(format: "%.1f%%", percentage)
        } else {
            integrityHealth = "100%"
        }
        
        let networkStatus: String
        switch networkMonitor.status {
        case .disconnected: networkStatus = "disconnected"
        case .connected: networkStatus = "connected"
        case .verified: networkStatus = "verified"
        case .captivePortal: networkStatus = "captive_portal"
        }
        
        return MetricsResponse(
            status: status,
            lastSuccessfulBackup: lastBackup,
            filesPending: integrityManager.filesPending,
            integrityHealth: integrityHealth,
            driveStatus: driveWatcher.status.label,
            photosStatus: photoWatcher.status.label,
            filesVaulted: driveWatcher.sessionVaultedCount,
            photosBackedUp: photoWatcher.sessionSavedCount,
            integrityVerified: integrityManager.filesVerified,
            integrityErrors: integrityManager.filesWithErrors,
            networkStatus: networkStatus,
            isPaused: persistence.isGlobalPaused,
            hostname: Host.current().localizedName ?? "Unknown",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            timestamp: Int64(Date().timeIntervalSince1970)
        )
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String, contentType: String = "text/plain") {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }
        
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Server: Anchor/1.0\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("❌ Failed to send response: \(error)")
                }
                connection.cancel()
            })
        }
    }
}
