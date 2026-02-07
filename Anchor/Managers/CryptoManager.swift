//
//  CryptoManager.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation
import CryptoKit
import CommonCrypto

class CryptoManager {
    static let shared = CryptoManager()
    
    private let kKeychainAccount = "anchor_encryption_key"
    private var symmetricKey: SymmetricKey?
    
    private let chunkSize = 1024 * 1024
    
    private let rawChunkSize = 10 * 1024 * 1024
    private let encryptedChunkSize = 12 + (10 * 1024 * 1024) + 16
    
    private init() {
        if let keyDataString = KeychainManager.shared.load(key: kKeychainAccount),
           let keyData = Data(base64Encoded: keyDataString) {
            self.symmetricKey = SymmetricKey(data: keyData)
        }
    }
    
    var isConfigured: Bool {
        return symmetricKey != nil
    }
    
    /// Generates a new identity for a fresh vault
    func createIdentity(password: String) throws -> VaultIdentity {
        let salt = randomData(count: 32)
        
        let key = try deriveKey(password: password, salt: salt)
        self.symmetricKey = key
        
        saveKeyToKeychain(key)
        
        let knownString = "ANCHOR_VERIFY".data(using: .utf8)!
        let sealedBox = try AES.GCM.seal(knownString, using: key)
        let token = sealedBox.combined!
        
        return VaultIdentity(salt: salt, vaultID: UUID(), verificationToken: token)
    }
    
    func unlock(password: String, identity: VaultIdentity) throws {
        let key = try deriveKey(password: password, salt: identity.salt)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: identity.verificationToken)
            let openedBox = try AES.GCM.open(sealedBox, using: key)
            
            guard let checkString = String(data: openedBox, encoding: .utf8),
                  checkString == "ANCHOR_VERIFY" else {
                throw CryptoError.invalidPassword
            }
        } catch {
            throw CryptoError.invalidPassword
        }
        
        self.symmetricKey = key
        saveKeyToKeychain(key)
    }
    
    func disableEncryption() {
        KeychainManager.shared.delete(key: kKeychainAccount)
        self.symmetricKey = nil
    }

    
    func encryptFile(source: URL) throws -> URL {
        guard let key = symmetricKey else { throw CryptoError.noKeyConfigured }
        
        let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let estimatedEncryptedSize = estimateEncryptedSize(sourceSize: sourceSize)
        let availableSpace = try getAvailableDiskSpace()
        let safetyBuffer: Int64 = 500 * 1024 * 1024
        
        if availableSpace < (estimatedEncryptedSize + safetyBuffer) {
            throw CryptoError.insufficientDiskSpace
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(UUID().uuidString + ".anchor")
        
        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        
        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: destURL)
        
        defer {
            try? reader.close()
            try? writer.close()
        }
        
        while true {
            autoreleasepool {
                let rawData = (try? reader.read(upToCount: rawChunkSize)) ?? Data()
                if rawData.isEmpty { return }
                let nonce = AES.GCM.Nonce()
                
                do {
                    let sealedBox = try AES.GCM.seal(rawData, using: key, nonce: nonce)
                    
                    if let combinedData = sealedBox.combined {
                        writer.write(combinedData)
                    }
                } catch {
                    print("Crypto Error on chunk: \(error)")
                }
            }
            
            if (try? reader.offset()) ?? 0 >= (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 {
                break
            }
        }
        
        return destURL
    }
    
    func decryptFile(source: URL, dest: URL) throws {
        guard let key = symmetricKey else { throw CryptoError.noKeyConfigured }
        
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        
        let reader = try FileHandle(forReadingFrom: source)
        let writer = try FileHandle(forWritingTo: dest)
        
        var decryptionError: Error? = nil
        
        defer {
            try? reader.close()
            try? writer.close()
            
            if decryptionError != nil {
                try? FileManager.default.removeItem(at: dest)
            }
        }
        
        let fileSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var currentOffset = 0

        while currentOffset < fileSize {
            autoreleasepool {
                let remainingBytes = fileSize - currentOffset
                let amountToRead = min(remainingBytes, encryptedChunkSize)

                guard let chunkData = try? reader.read(upToCount: amountToRead) else { return }
                currentOffset += chunkData.count

                do {
                    let sealedBox = try AES.GCM.SealedBox(combined: chunkData)
                    let decryptedData = try AES.GCM.open(sealedBox, using: key)
                    writer.write(decryptedData)
                } catch {
                    print("Decryption Error at offset \(currentOffset): \(error)")
                    decryptionError = error
                }
            }
        }
        
        if let error = decryptionError {
            throw error
        }
    }

    
    private func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        KeychainManager.shared.save(key: kKeychainAccount, value: keyData.base64EncodedString())
    }
    
    private func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Array(password.utf8)
        let saltData = Array(salt)
        
        var derivedKeyData = Data(count: 32)
        let derivedCount = derivedKeyData.count
        
        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            saltData.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    saltData.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    10000,
                    derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                    derivedCount
                )
            }
        }
        
        guard derivationStatus == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }
        
        return SymmetricKey(data: derivedKeyData)
    }
    
    func prepareFileForUpload(source: URL) throws -> (url: URL, isEncrypted: Bool) {
        if isConfigured {
            if source.pathExtension == "anchor" { return (source, true) }
            let encryptedURL = try encryptFile(source: source)
            return (encryptedURL, true)
        } else {
            return (source, false)
        }
    }
    
    func cleanup(url: URL, wasEncrypted: Bool) {
        if wasEncrypted {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func randomData(count: Int) -> Data {
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        return data
    }
    
    private func getAvailableDiskSpace() throws -> Int64 {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
            throw CryptoError.insufficientDiskSpace
        }
        return capacity
    }
    
    private func estimateEncryptedSize(sourceSize: Int64) -> Int64 {
        let numChunks = (sourceSize + Int64(rawChunkSize) - 1) / Int64(rawChunkSize)
        let overhead = 12 + 16
        return sourceSize + (numChunks * Int64(overhead))
    }
}
