//
//  NetworkMonitor.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    enum Status {
        case disconnected
        case connected
        case verified
        case captivePortal
    }
    
    @Published var status: Status = .disconnected
    @Published var isExpensive = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.anchor.network")
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isExpensive = path.isExpensive
                
                if path.status == .satisfied {
                    self?.status = .connected
                    self?.verifyConnectivity()
                } else {
                    self?.status = .disconnected
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    func verifyConnectivity() {
        guard status != .disconnected else { return }
        guard let url = URL(string: "http://captive.apple.com/hotspot-detect.html") else { return }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 5.0
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let _ = error {
                    self?.status = .disconnected
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   httpResponse.statusCode == 200,
                   let data = data,
                   let responseString = String(data: data, encoding: .utf8),
                   responseString.trimmingCharacters(in: .whitespacesAndNewlines) == "Success" {
                    
                    self?.status = .verified
                    print("✅ Internet Connection Verified")
                    
                } else {
                    self?.status = .captivePortal
                    print("⚠️ Captive Portal Detected")
                }
            }
        }
        task.resume()
    }
}
