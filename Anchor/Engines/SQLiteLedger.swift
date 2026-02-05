//
//  SQLiteLedger.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import SQLite3

class SQLiteLedger {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.anchor.sqlite", attributes: .concurrent)
    
    init() {
        let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("anchor_ledger.sqlite")
        
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("❌ Error opening SQLite database")
            return
        }
        
        createTable()
        
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }
    
    deinit {
        sqlite3_close(db)
    }
        
    private func createTable() {
        let query = "CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, gen_id TEXT);"
        
        if sqlite3_exec(db, query, nil, nil, nil) != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("❌ Error creating table: \(errMsg)")
        }
    }
        
    func shouldProcess(relativePath: String, currentGenID: String) -> Bool {
        return queue.sync {
            let query = "SELECT gen_id FROM files WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        let savedGenID = String(cString: cString)
                        sqlite3_finalize(statement)
                        
                        return savedGenID != currentGenID
                    }
                }
            }
            
            sqlite3_finalize(statement)
            
            return true
        }
    }
    
    func removeEntry(relativePath: String) {
        queue.async(flags: .barrier) {
            let query = "DELETE FROM files WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("⚠️ SQLite Delete Error")
                }
            }
            sqlite3_finalize(statement)
        }
    }
    
    func markAsProcessed(relativePath: String, genID: String) {
        queue.async(flags: .barrier) {
            let query = "INSERT OR REPLACE INTO files (path, gen_id) VALUES (?, ?);"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (genID as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    print("⚠️ SQLite Write Error")
                }
            }
            sqlite3_finalize(statement)
        }
    }
}
