//
//  SQLiteLedger.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class SQLiteLedger: @unchecked Sendable {
    private var db: OpaquePointer?
    // Serial queue for writes to prevent locking, concurrent for reads
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
        if sqlite3_open(url.path, &db) != SQLITE_OK { return false }
        
        sqlite3_busy_timeout(db, 5000)
        
        _ = execute(sql: "PRAGMA journal_mode=WAL;")
        
        _ = execute(sql: "PRAGMA synchronous=NORMAL;")
        
        return true
    }
    
    func renamePath(from oldPath: String, to newPath: String) {
        queue.async(flags: .barrier) {
            let exactQuery = "UPDATE files SET path = ? WHERE path = ?;"
            var stmt1: OpaquePointer?
            if sqlite3_prepare_v2(self.db, exactQuery, -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, (newPath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt1, 2, (oldPath as NSString).utf8String, -1, SQLITE_TRANSIENT)
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
                sqlite3_bind_text(stmt2, 1, (newPath as NSString).utf8String, -1, SQLITE_TRANSIENT) // Replacement prefix
                sqlite3_bind_text(stmt2, 2, (oldPath as NSString).utf8String, -1, SQLITE_TRANSIENT) // Length calculator
                sqlite3_bind_text(stmt2, 3, (oldPath as NSString).utf8String, -1, SQLITE_TRANSIENT) // Matcher
                sqlite3_step(stmt2)
            }
            sqlite3_finalize(stmt2)
            
            print("📖 Ledger updated: \(oldPath) -> \(newPath)")
        }
    }
    
    private func handleCorruption(at url: URL) {
        print("🔥 CORRUPTION DETECTED: Resetting Ledger...")
        
        if db != nil { sqlite3_close(db); db = nil }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        
        DispatchQueue.main.async {
            NotificationManager.shared.send(
                title: "Database Reset",
                body: "Anchor's database was corrupted and has been reset. A full re-scan is starting now.",
                type: .vaultIssue
            )
        }
    }
        
    private func createTable() {
        _ = execute(sql: "CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, gen_id TEXT);")
        _ = execute(sql: "CREATE TABLE IF NOT EXISTS uploads (path TEXT PRIMARY KEY, upload_id TEXT, timestamp DOUBLE);")
    }
    
    func getStoredCasing(for relativePath: String) -> String? {
        return queue.sync {
            let query = "SELECT path FROM files WHERE path = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        let result = String(cString: cString)
                        sqlite3_finalize(statement)
                        return result
                    }
                }
            }
            sqlite3_finalize(statement)
            return nil
        }
    }
    
    func wipe() {
        queue.async(flags: .barrier) {
            _ = self.execute(sql: "DELETE FROM files;")
            _ = self.execute(sql: "DELETE FROM uploads;")
            print("☢️ Ledger Wiped Clean.")
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
                        uploads.append(ActiveUpload(relativePath: String(cString: pathC),
                                                    uploadID: String(cString: idC),
                                                    timestamp: sqlite3_column_double(statement, 2)))
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
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
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
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, (uploadID as NSString).utf8String, -1, SQLITE_TRANSIENT)
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
            sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }
        
    func shouldProcess(relativePath: String, currentGenID: String) -> Bool {
        return queue.sync {
            let query = "SELECT gen_id FROM files WHERE path = ?;"
            var statement: OpaquePointer?
            var shouldUpload = true
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        let savedGenID = String(cString: cString)
                        shouldUpload = (savedGenID != currentGenID)
                    }
                }
            }
            sqlite3_finalize(statement)
            return shouldUpload
        }
    }
    
    func deleteRecords(prefix: String) {
        queue.async(flags: .barrier) {
            let pattern = prefix + "%"
            
            let queryFiles = "DELETE FROM files WHERE path LIKE ?;"
            var stmt1: OpaquePointer?
            
            if sqlite3_prepare_v2(self.db, queryFiles, -1, &stmt1, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt1, 1, (pattern as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt1) != SQLITE_DONE {
                    self.logError("Write Error (deleteRecords files)")
                }
            }
            sqlite3_finalize(stmt1)
            
            let queryUploads = "DELETE FROM uploads WHERE path LIKE ?;"
            var stmt2: OpaquePointer?
            
            if sqlite3_prepare_v2(self.db, queryUploads, -1, &stmt2, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt2, 1, (pattern as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt2) != SQLITE_DONE {
                    self.logError("Write Error (deleteRecords uploads)")
                }
            }
            sqlite3_finalize(stmt2)
            
            print("🧹 Ledger Pruned: Removed items starting with '\(prefix)'")
        }
    }
    
    func getContents(of relativePath: String) -> [FileItem] {
        return queue.sync {
            var items: Set<FileItem> = []
            let prefix = relativePath.isEmpty ? "" : relativePath + "/"
            
            let query = "SELECT path FROM files WHERE path LIKE ? || '%';"
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (prefix as NSString).utf8String, -1, SQLITE_TRANSIENT)
                
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let cString = sqlite3_column_text(statement, 0) {
                        let fullPath = String(cString: cString)
                        
                        if fullPath == prefix || fullPath == String(prefix.dropLast()) { continue }
                        
                        let remainder = String(fullPath.dropFirst(prefix.count))
                        let components = remainder.split(separator: "/")
                        
                        if let firstComponent = components.first {
                            let name = String(firstComponent)
                            let isFolder = components.count > 1
                            let itemPath = prefix + name
                            items.insert(FileItem(name: name, fullPath: itemPath, isFolder: isFolder))
                        }
                    }
                }
            }
            sqlite3_finalize(statement)
            
            return items.sorted {
                ($0.isFolder && !$1.isFolder) || ($0.isFolder == $1.isFolder && $0.name < $1.name)
            }
        }
    }
    
    func removeEntry(relativePath: String) {
        queue.async(flags: .barrier) {
            let query = "DELETE FROM files WHERE path = ?;"
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(self.db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if sqlite3_step(statement) != SQLITE_DONE {
                    self.logError("Write Error (removeEntry)")
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
                sqlite3_bind_text(statement, 1, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, (genID as NSString).utf8String, -1, SQLITE_TRANSIENT)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    self.logError("Write Error (markAsProcessed)")
                }
            } else {
                self.logError("Prepare Error (markAsProcessed)")
            }
            sqlite3_finalize(statement)
        }
    }
    
    func execute(sql: String) -> Bool {
        return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
    
    private func logError(_ context: String) {
        if let errorPointer = sqlite3_errmsg(db) {
            let message = String(cString: errorPointer)
            print("⚠️ SQLite \(context): \(message)")
        } else {
            print("⚠️ SQLite \(context): Unknown error")
        }
    }
}
