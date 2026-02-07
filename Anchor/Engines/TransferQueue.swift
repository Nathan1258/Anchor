//
//  TransferQueue.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//
import Foundation

actor TransferQueue {
    static let shared = TransferQueue()
    
    private var activeTaskCount = 0
    private let maxConcurrent = 4
    private var queue: [CheckedContinuation<Void, Never>] = []
    
    func enqueue() async {
        if activeTaskCount < maxConcurrent {
            activeTaskCount += 1
            return
        }
        
        await withCheckedContinuation { continuation in
            queue.append(continuation)
        }
    }
    
    func taskFinished() {
        if !queue.isEmpty {
            let nextContinuation = queue.removeFirst()
            nextContinuation.resume()
        } else {
            activeTaskCount -= 1
        }
    }
}
