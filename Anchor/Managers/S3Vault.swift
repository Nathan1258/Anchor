//
//  S3Vault.swift
//  Anchor
//
//  Created by Nathan Ellis on 06/02/2026.
//
import Foundation
import AWSS3
import AwsCommonRuntimeKit
import Smithy
import AWSSDKIdentity
import SmithyIdentity
import AWSClientRuntime
internal import ClientRuntime

final class S3Vault: VaultProvider {
    
    private let client: S3Client
    private let bucket: String
    
    private let PART_SIZE: Int64 = 5 * 1024 * 1024
    
    typealias CompletedPart = S3ClientTypes.CompletedPart
    typealias CompletedMultipartUpload = S3ClientTypes.CompletedMultipartUpload
    
    private init(client: S3Client, bucket: String) {
        self.client = client
        self.bucket = bucket
    }
    
    static func create(config: S3Config) async throws -> S3Vault {
        var s3Config = try await S3Client.S3ClientConfig(
            awsCredentialIdentityResolver: StaticAWSCredentialIdentityResolver(
                AWSCredentialIdentity(
                    accessKey: config.accessKey,
                    secret: config.secretKey
                )
            ),
            region: config.region
        )
        
        if config.endpoint != "https://s3.amazonaws.com" {
            s3Config.endpoint = config.endpoint
            s3Config.forcePathStyle = true
        }
        
        let client = S3Client(config: s3Config)
        return S3Vault(client: client, bucket: config.bucket)
    }
    
    func wipe(prefix: String) async throws {
        var continuationToken: String? = nil
        
        repeat {
            let listInput = ListObjectsV2Input(
                bucket: self.bucket,
                continuationToken: continuationToken,
                prefix: prefix
            )
            
            let listOutput = try await client.listObjectsV2(input: listInput)
            continuationToken = listOutput.nextContinuationToken
            
            guard let objects = listOutput.contents, !objects.isEmpty else { break }
            
            let objectIds = objects.compactMap { obj -> S3ClientTypes.ObjectIdentifier? in
                guard let key = obj.key else { return nil }
                if key == "anchor_identity.json" { return nil }
                return S3ClientTypes.ObjectIdentifier(key: key)
            }
            
            if objectIds.isEmpty { break }
            
            let deleteInput = DeleteObjectsInput(
                bucket: self.bucket,
                delete: S3ClientTypes.Delete(objects: objectIds, quiet: true)
            )
            
            _ = try await client.deleteObjects(input: deleteInput)
            print("🔥 S3 Batch Delete: Removed \(objectIds.count) items...")
            
        } while continuationToken != nil
        
        print("✅ S3 Wipe Complete for prefix: '\(prefix)'")
    }
    
    func listFiles(at path: String) async throws -> [FileMetadata] {
        var prefix = path
        if !prefix.isEmpty && !prefix.hasSuffix("/") {
            prefix += "/"
        }
        
        let input = ListObjectsV2Input(
            bucket: self.bucket,
            delimiter: "/",
            prefix: prefix
        )
        
        let output = try await client.listObjectsV2(input: input)
        var results: [FileMetadata] = []
        
        if let folders = output.commonPrefixes {
            for folder in folders {
                guard let folderPrefix = folder.prefix else { continue }
                
                let name = folderPrefix.dropLast().split(separator: "/").last.map(String.init) ?? folderPrefix
                
                let cleanPath = folderPrefix.hasSuffix("/") ? String(folderPrefix.dropLast()) : folderPrefix
                
                results.append(FileMetadata(
                    name: name,
                    path: cleanPath,
                    isFolder: true,
                    size: nil,
                    lastModified: nil
                ))
            }
        }
        
        if let files = output.contents {
            for file in files {
                guard let key = file.key else { continue }
                
                if key == prefix { continue }
                
                let name = key.split(separator: "/").last.map(String.init) ?? key
                
                results.append(FileMetadata(
                    name: name,
                    path: key,
                    isFolder: false,
                    size: file.size,
                    lastModified: file.lastModified
                ))
            }
        }
        
        return results
    }
    
    func listAllFiles() async throws -> [String] {
        var paths: [String] = []
        var continuationToken: String? = nil
        
        print("🔎 Starting S3 Indexing...")
        
        repeat {
            let input = ListObjectsV2Input(
                bucket: self.bucket,
                continuationToken: continuationToken
            )
            let output = try await client.listObjectsV2(input: input)
            continuationToken = output.nextContinuationToken
            
            if let objects = output.contents {
                let batch = objects.compactMap { $0.key }
                paths.append(contentsOf: batch)
            }
        } while continuationToken != nil
        
        print("✅ Indexing Complete. Found \(paths.count) items.")
        return paths
    }
    
    func downloadFile(relativePath: String, to localURL: URL) async throws {
        print("⬇️ Requesting: \(relativePath)")
        
        let input = GetObjectInput(bucket: self.bucket, key: relativePath)
        let output = try await client.getObject(input: input)
        
        guard let body = output.body else {
            throw NSError(domain: "Anchor", code: 404, userInfo: [NSLocalizedDescriptionKey: "Empty body from S3"])
        }
        
        guard let data = try await body.readData() else {
            throw NSError(domain: "Anchor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to read data from body"])
        }
        
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        
        try data.write(to: localURL)
    }
    
    func loadIdentity() async throws -> VaultIdentity? {
        let input = GetObjectInput(bucket: self.bucket, key: "anchor_identity.json")
        
        do {
            let output = try await client.getObject(input: input)
            guard let body = output.body else { return nil }
            
            let data = try await body.readData() ?? Data()
            
            return try JSONDecoder().decode(VaultIdentity.self, from: data)
        } catch {
            let errString = String(describing: error)
            if errString.contains("NoSuchKey") || errString.contains("NotFound") {
                return nil
            }
            throw error
        }
    }
    
    func saveIdentity(_ identity: VaultIdentity) async throws {
        let data = try JSONEncoder().encode(identity)
        let input = PutObjectInput(
            body: .data(data),
            bucket: self.bucket,
            key: "anchor_identity.json"
        )
        _ = try await client.putObject(input: input)
        print("🔐 Identity file saved to S3")
    }
    
    func saveFile(source: URL, relativePath: String, checkCancellation: (() -> Bool)? = nil) async throws {
        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        
        if isDirectory {
            try await savePackage(source: source, relativePath: relativePath)
        } else {
            try await uploadSingleFile(source: source, key: relativePath, checkCancellation: checkCancellation)
        }
    }
    
    private func savePackage(source: URL, relativePath: String) async throws {
        let zipName = source.lastPathComponent + ".zip"
        let tempDir = FileManager.default.temporaryDirectory
        let tempZipURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(zipName)
        
        try FileManager.default.createDirectory(at: tempZipURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-y", tempZipURL.path, source.lastPathComponent]
        process.currentDirectoryURL = source.deletingLastPathComponent()
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: tempZipURL.path) else {
            throw NSError(domain: "Anchor", code: 501, userInfo: [NSLocalizedDescriptionKey: "Failed to zip package"])
        }
        
        let uploadKey = relativePath.hasSuffix(".zip") ? relativePath : relativePath + ".zip"
        
        print("📦 Zipped Package: \(source.lastPathComponent) -> \(uploadKey)")
        
        do {
            try await uploadSingleFile(source: tempZipURL, key: uploadKey)
            try FileManager.default.removeItem(at: tempZipURL)
        } catch {
            try? FileManager.default.removeItem(at: tempZipURL)
            throw error
        }
    }
    
    func uploadSingleFile(source: URL, key: String, checkCancellation: (() -> Bool)? = nil) async throws {
        let fileSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)) ?? 0
        let MIN_PART_SIZE: Int64 = 5 * 1024 * 1024
        
        if fileSize < PART_SIZE {
            try await simpleUpload(source: source, relativePath: key)
            return
        }
        
        let calculatedPartSize = max(MIN_PART_SIZE, fileSize / 10000)
        let totalParts = Int(ceil(Double(fileSize) / Double(calculatedPartSize)))
        
        let ledger = SQLiteLedger()
        var uploadID = ledger.getActiveUploadID(relativePath: key)
        
        if uploadID == nil {
            let createInput = CreateMultipartUploadInput(bucket: bucket, key: key)
            let response = try await client.createMultipartUpload(input: createInput)
            uploadID = response.uploadId
            if let id = uploadID {
                ledger.saveUploadID(relativePath: key, uploadID: id)
                print("🚀 Started Multipart Upload: \(key)")
            }
        }
        
        guard let currentUploadID = uploadID else {
            throw NSError(domain: "Anchor", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to get Upload ID"])
        }
        
        var uploadedParts: [CompletedPart] = []
        
        do {
            let listInput = ListPartsInput(bucket: bucket, key: key, uploadId: currentUploadID)
            let listResponse = try await client.listParts(input: listInput)
            
            if let parts = listResponse.parts {
                for part in parts {
                    uploadedParts.append(CompletedPart(eTag: part.eTag, partNumber: part.partNumber))
                }
            }
            
            let fileHandle = try FileHandle(forReadingFrom: source)
            defer { try? fileHandle.close() }
            
            
            for partNumber in 1...totalParts {
                if let checkCancellation, checkCancellation() {
                    print("🛑 Upload Cancelled by User: \(key)")
                    
                    let uploadId = currentUploadID
                    Task {
                        try? await self.abortUpload(key: key, uploadId: uploadId)
                    }
                    
                    throw NSError(domain: "Anchor", code: 999, userInfo: [NSLocalizedDescriptionKey: "Upload Cancelled"])
                }
                if uploadedParts.contains(where: { $0.partNumber == partNumber }) {
                    print("⏩ Skipping part \(partNumber) (Already uploaded)")
                    continue
                }
                
                let offset = UInt64((partNumber - 1)) * UInt64(calculatedPartSize)
                try fileHandle.seek(toOffset: offset)
                let chunkData = try fileHandle.read(upToCount: Int(calculatedPartSize)) ?? Data()
                
                if chunkData.isEmpty { break }
                
                print("⬆️ Uploading part \(partNumber)/\(totalParts)...")
                let uploadPartInput = UploadPartInput(
                    body: .data(chunkData),
                    bucket: bucket,
                    key: key,
                    partNumber: partNumber,
                    uploadId: currentUploadID
                )
                
                let partResponse = try await client.uploadPart(input: uploadPartInput)
                uploadedParts.append(CompletedPart(eTag: partResponse.eTag, partNumber: partNumber))
            }
            
            let completeInput = CompleteMultipartUploadInput(
                bucket: bucket,
                key: key,
                multipartUpload: CompletedMultipartUpload(parts: uploadedParts.sorted { $0.partNumber! < $1.partNumber! }),
                uploadId: currentUploadID
            )
            
            _ = try await client.completeMultipartUpload(input: completeInput)
            
            ledger.removeUploadID(relativePath: key)
            print("✅ Multipart Upload Complete: \(key)")
            
        } catch {
            print("⚠️ Multipart Error: \(error)")
            
            if !FileManager.default.fileExists(atPath: source.path) {
                print("🗑️ Source file missing. Aborting S3 upload to cleanup.")
                try? await abortUpload(key: key, uploadId: currentUploadID)
                ledger.removeUploadID(relativePath: key)
            }
            throw error
        }
    }
    
    func moveItem(from oldPath: String, to newPath: String) async throws {
        let listInput = ListObjectsV2Input(bucket: self.bucket, prefix: oldPath)
        let output = try await client.listObjectsV2(input: listInput)
        
        guard let objects = output.contents, !objects.isEmpty else { return }
        
        print("☁️ S3 Move Detected: Processing \(objects.count) items...")
        
        for object in objects {
            guard let oldKey = object.key else { continue }
            
            let suffix = String(oldKey.dropFirst(oldPath.count))
            let newKey = newPath + suffix
            
            let copyInput = CopyObjectInput(
                bucket: self.bucket,
                copySource: "\(self.bucket)/\(oldKey)",
                key: newKey
            )
            
            _ = try await client.copyObject(input: copyInput)
            
            let deleteInput = DeleteObjectInput(bucket: self.bucket, key: oldKey)
            _ = try await client.deleteObject(input: deleteInput)
        }
        
        print("✅ S3 Smart Move Complete: \(oldPath) -> \(newPath)")
    }
    
    private func simpleUpload(source: URL, relativePath: String) async throws {
        let data = try Data(contentsOf: source) 
        let input = PutObjectInput(body: .data(data), bucket: bucket, key: relativePath)
        _ = try await client.putObject(input: input)
        print("☁️ Simple Upload Success: \(relativePath)")
    }
    
    func abortUpload(key: String, uploadId: String) async throws {
        let input = AbortMultipartUploadInput(bucket: bucket, key: key, uploadId: uploadId)
        _ = try await client.abortMultipartUpload(input: input)
    }
    
    func deleteFile(relativePath: String) async throws {
        let input = DeleteObjectInput(bucket: self.bucket, key: relativePath)
        _ = try await client.deleteObject(input: input)
        
        let zipInput = DeleteObjectInput(bucket: self.bucket, key: relativePath + ".zip")
        _ = try await client.deleteObject(input: zipInput)
        
        print("☁️ S3 Delete Success: \(relativePath) (and potential .zip)")
    }
    
    func fileExists(relativePath: String) async -> Bool {
        let input = HeadObjectInput(
            bucket: self.bucket,
            key: relativePath
        )
        
        do {
            _ = try await client.headObject(input: input)
            return true
        } catch {
            return false
        }
    }
    
    func testConnection() async throws {
        let testKey = ".anchor_connection_test"
        let testData = "Anchor Connection Verification".data(using: .utf8)!
        
        let putInput = PutObjectInput(
            body: .data(testData),
            bucket: self.bucket,
            key: testKey
        )
        _ = try await client.putObject(input: putInput)
        
        let deleteInput = DeleteObjectInput(
            bucket: self.bucket,
            key: testKey
        )
        _ = try await client.deleteObject(input: deleteInput)
        
        print("✅ Connection Test Passed")
    }
}
