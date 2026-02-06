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

class S3Vault: VaultProvider {
    
    private let client: S3Client
    private let bucket: String
    
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
    
    func saveFile(source: URL, relativePath: String) async throws {
        let fileData = try Data(contentsOf: source)
        
        let input = PutObjectInput(
            body: .data(fileData),
            bucket: self.bucket,
            key: relativePath
        )
        
        do {
            _ = try await client.putObject(input: input)
            print("☁️ S3 Upload Success: \(relativePath)")
        } catch let error as AWSServiceError {
            // 🔍 DEEP DEBUGGING
            print("❌ S3 UPLOAD FAILED [AWS Service Error]")
            print("   - Message: \(error.message ?? "None")")
        } catch {
            print("❌ Standard S3 Error: \(error)")
            throw error
        }
    }
    
    func deleteFile(relativePath: String) async throws {
        let input = DeleteObjectInput(
            bucket: self.bucket,
            key: relativePath
        )
        
        _ = try await client.deleteObject(input: input)
        print("☁️ S3 Delete Success: \(relativePath)")
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
