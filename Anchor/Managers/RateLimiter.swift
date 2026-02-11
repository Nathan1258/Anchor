//
//  RateLimiter.swift
//  Anchor
//
//  Created by Claude on 11/02/2026.
//
import Foundation

class RateLimiter {
    static let shared = RateLimiter()
    
    private var bytesTransferred: Int64 = 0
    private var lastResetTime = Date()
    private let queue = DispatchQueue(label: "com.anchor.ratelimiter")
    private let resetInterval: TimeInterval = 1.0
    
    private init() {}
    
    func shouldThrottle(bytesPerSecond: Int64, maxMBps: Double) -> TimeInterval {
        guard maxMBps > 0 else { return 0 }
        
        let maxBytesPerSecond = Int64(maxMBps * 1_000_000)
        
        return queue.sync {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastResetTime)
            
            if elapsed >= resetInterval {
                bytesTransferred = 0
                lastResetTime = now
            }
            
            if bytesTransferred + bytesPerSecond > maxBytesPerSecond {
                let delay = resetInterval - elapsed
                return max(0, delay)
            }
            
            bytesTransferred += bytesPerSecond
            return 0
        }
    }
    
    func recordBytes(_ bytes: Int64) {
        queue.sync {
            let now = Date()
            let elapsed = now.timeIntervalSince(lastResetTime)
            
            if elapsed >= resetInterval {
                bytesTransferred = bytes
                lastResetTime = now
            } else {
                bytesTransferred += bytes
            }
        }
    }
    
    func reset() {
        queue.sync {
            bytesTransferred = 0
            lastResetTime = Date()
        }
    }
}
