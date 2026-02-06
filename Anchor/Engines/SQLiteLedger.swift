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
        
        if !openDatabase(at: fileURL) {
            handleCorruption(at: fileURL)
            
            if !openDatabase(at: fileURL) {
                print("❌ CRITICAL: Failed to initialize fresh database.")
            }
        }
        
        createTable()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func openDatabase(at url: URL) -> Bool {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            return false
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA quick_check;", -1, &statement, nil) == SQLITE_OK {
            let stepResult = sqlite3_step(statement)
            sqlite3_finalize(statement)
            
            if stepResult == SQLITE_ROW {
                return sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK
            }
        }
        
        sqlite3_close(db)
        db = nil
        return false
    }
    
    func renamePath(from oldPath: String, to newPath: String) {
        queue.async(flags: .barrier) {
            let exactQuery = "UPDATE files SET path = ? WHERE path = ?;"
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(self.db, exactQuery, -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, (newPath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt1, 2, (oldPath as NSString).utf8String, -1, nil)
                sqlite3_step(stmt1)
            }
            sqlite3_finalize(stmt1)
            
            let childrenQuery = """
                UPDATE files 
                SET path = ? || SUBSTR(path, LENGTH(?) + 1) 
                WHERE path LIKE ? || '/%';
            """
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(self.db, childrenQuery, -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, (newPath as NSString).utf8String, -1, nil) // Replacement prefix
                sqlite3_bind_text(stmt2, 2, (oldPath as NSString).utf8String, -1, nil) // Length calculator
                sqlite3_bind_text(stmt2, 3, (oldPath as NSString).utf8String, -1, nil) // Matcher
                sqlite3_step(stmt2)
            }
            sqlite3_finalize(stmt2)
            
            print("📖 Ledger updated: \(oldPath) -> \(newPath)")
        }
    }
    
    private func handleCorruption(at url: URL) {
        print("🔥 CORRUPTION DETECTED: Resetting Ledger...")
        
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
        
        let fileManager = FileManager.default
        let path = url.path
        
        do {
            if fileManager.fileExists(atPath: path) { try fileManager.removeItem(atPath: path) }
            if fileManager.fileExists(atPath: path + "-wal") { try fileManager.removeItem(atPath: path + "-wal") }
            if fileManager.fileExists(atPath: path + "-shm") { try fileManager.removeItem(atPath: path + "-shm") }
        } catch {
            print("⚠️ Failed to cleanup corrupted files: \(error)")
        }
        
        DispatchQueue.main.async {
            NotificationManager.shared.send(
                title: "Database Reset",
                body: "Anchor's database was corrupted and has been reset. A full re-scan is starting now.",
                type: .vaultIssue
            )
        }
    }
        
    private func createTable() {
        var query = "CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, gen_id TEXT);"
        if sqlite3_exec(db, query, nil, nil, nil) != SQLITE_OK { print("❌ Error creating files table") }
        
        query = "CREATE TABLE IF NOT EXISTS uploads (path TEXT PRIMARY KEY, upload_id TEXT, timestamp DOUBLE);"
        if sqlite3_exec(db, query, nil, nil, nil) != SQLITE_OK { print("❌ Error creating uploads table") }
    }
    
    func getStoredCasing(for relativePath: String) -> String? {
        return queue.sync {
            let query = "SELECT path FROM files WHERE path = ?;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        let exactStoredPath = String(cString: cString)
                        sqlite3_finalize(statement)
                        return exactStoredPath
                    }
                }
            }
            sqlite3_finalize(statement)
            return nil
        }
    }
    
    func wipe() {
        queue.async(flags: .barrier) {
            let queryFiles = "DELETE FROM files;"
            if sqlite3_exec(self.db, queryFiles, nil, nil, nil) != SQLITE_OK {
                print("⚠️ Error wiping files table")
            }
            
            let queryUploads = "DELETE FROM uploads;"
            if sqlite3_exec(self.db, queryUploads, nil, nil, nil) != SQLITE_OK {
                print("⚠️ Error wiping uploads table")
            }
            
            print("☢️ Ledger Wiped Clean (Vault Switch).")
        }
    }
    
    func getAllTrackedPaths() -> [String] {
        return queue.sync {
            var paths: [String] = []
            let query = "SELECT path FROM files;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        paths.append(String(cString: cString))
                    }
                }
            }
            sqlite3_finalize(statement)
            return paths
        }
    }
    
    func getAllActiveUploads() -> [ActiveUpload] {
        return queue.sync {
            var uploads: [ActiveUpload] = []
            let query = "SELECT path, upload_id, timestamp FROM uploads;"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let pathC = sqlite3_column_text(statement, 0),
                       let idC = sqlite3_column_text(statement, 1) {
                        let path = String(cString: pathC)
                        let id = String(cString: idC)
                        let time = sqlite3_column_double(statement, 2)
                        uploads.append(ActiveUpload(relativePath: path, uploadID: id, timestamp: time))
                    }
                }
            }
            sqlite3_finalize(statement)
            return uploads
        }
    }
    
    func getActiveUploadID(relativePath: String) -> String? {
        return queue.sync {
            let query = "SELECT upload_id FROM uploads WHERE path = ?;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
                if sqlite3_step(statement) == SQLITE_ROW, let cString = sqlite3_column_text(statement, 0) {
                    return String(cString: cString)
                }
            }
            return nil
        }
    }
    
    func saveUploadID(relativePath: String, uploadID: String) {
        queue.async(flags: .barrier) {
            let query = "INSERT OR REPLACE INTO uploads (path, upload_id, timestamp) VALUES (?, ?, ?);"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (uploadID as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
                sqlite3_step(statement)
            }
        }
    }
    
    func removeUploadID(relativePath: String) {
        queue.async(flags: .barrier) {
            let query = "DELETE FROM uploads WHERE path = ?;"
            var statement: OpaquePointer?
            sqlite3_prepare_v2(self.db, query, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
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
