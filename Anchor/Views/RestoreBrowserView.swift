//
//  RestoreBrowserView.swift
//  Anchor
//
//  Created by Nathan Ellis on 07/02/2026.
//
import SwiftUI

struct RestoreBrowserView: View {
    @StateObject private var viewModel = RestoreBrowserViewModel()
    @State private var isRestoring = false
    
    var body: some View {
        VStack(spacing: 0) {
            
            HStack(spacing: 4) {
                Button(action: { viewModel.navigateUp() }) {
                    Image(systemName: "arrow.up")
                }
                .disabled(viewModel.currentPath.isEmpty)
                .buttonStyle(.borderless)
                .padding(.trailing, 8)
                
                Button(action: { viewModel.navigateTo(componentIndex: -1) }) {
                    Image(systemName: "house.fill")
                        .foregroundColor(viewModel.currentPath.isEmpty ? .blue : .primary)
                }
                .buttonStyle(.borderless)
                
                ForEach(Array(viewModel.pathComponents.enumerated()), id: \.offset) { index, folder in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button(folder) {
                        viewModel.navigateTo(componentIndex: index)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(index == viewModel.pathComponents.count - 1 ? .blue : .primary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
            
            List {
                if viewModel.items.isEmpty {
                    Text("Folder is empty")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding()
                } else {
                    ForEach(viewModel.items) { item in
                        FileRow(item: item, isSelected: viewModel.isSelected(item)) {
                            if item.isFolder {
                                viewModel.openFolder(item)
                            } else {
                                viewModel.toggleSelection(item)
                            }
                        } onToggle: {
                            viewModel.toggleSelection(item)
                        }
                    }
                }
            }
            .listStyle(.inset)
            
            HStack {
                Text("\(viewModel.selectedItemsCount) items selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isRestoring {
                    ProgressView().controlSize(.small)
                    Text("Restoring...")
                        .font(.caption)
                } else {
                    Button("Restore Selected") {
                        performRestore()
                    }
                    .disabled(viewModel.selectedPaths.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .top)
        }
    }
    
    func performRestore() {
        guard !viewModel.selectedPaths.isEmpty else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Restore Here"
        panel.message = "Choose a folder to save your restored files."
        
        panel.begin { response in
            if response == .OK, let destinationURL = panel.url {
                
                self.isRestoring = true
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
                let folderName = "Restored \(formatter.string(from: Date()))"
                let restoreRoot = destinationURL.appendingPathComponent(folderName)
                
                try? FileManager.default.createDirectory(at: restoreRoot, withIntermediateDirectories: true)
                
                Task {
                    await self.executeRestore(to: restoreRoot)
                }
            }
        }
    }
    
    func executeRestore(to destination: URL) async {
        var queue = Array(viewModel.selectedPaths)
        
        var successCount = 0
        var failCount = 0
        var processedCount = 0
        let maxFiles = 1000
        
        let providerType = PersistenceManager.shared.driveVaultType
        guard let provider = try? await VaultFactory.getProvider(type: providerType) else { return }
        let rootFolder = "drive"

        while !queue.isEmpty && processedCount < maxFiles {
            let relativePath = queue.removeFirst()
            processedCount += 1
            
            let normalizedRelative = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let fullRemotePath = (rootFolder as NSString).appendingPathComponent(normalizedRelative)
            let localFileDest = destination.appendingPathComponent(normalizedRelative)
            
            var downloadResult: Result<URL, Error>? = nil
            var isEncrypted = false
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            
            do {
                try await provider.downloadFile(relativePath: fullRemotePath + ".anchor", to: tempURL)
                downloadResult = .success(tempURL)
                isEncrypted = true
            } catch {
                do {
                    try await provider.downloadFile(relativePath: fullRemotePath, to: tempURL)
                    downloadResult = .success(tempURL)
                    isEncrypted = false
                } catch {
                    if let children = try? await provider.listFiles(at: fullRemotePath) {
                        if !children.isEmpty {
                            print("📂 Found folder: \(relativePath), adding \(children.count) items to queue.")
                            
                            let childPaths = children.compactMap { file -> String? in
                                var path = file.path
                                
                                if path.hasPrefix(rootFolder + "/") {
                                    path = String(path.dropFirst(rootFolder.count + 1))
                                }
                                
                                if path.hasSuffix(".anchor") {
                                    path = String(path.dropLast(7))
                                }
                                
                                if path.contains("anchor_identity.json") { return nil }
                                
                                return path
                            }
                            
                            queue.append(contentsOf: childPaths)
                            continue
                        }
                    }
                }
            }
            
            if let result = downloadResult {
                 switch result {
                 case .success(let url):
                     let sourceURL = url
                     let destURL = localFileDest
                     let encrypted = isEncrypted
                     let path = relativePath
                     
                     let success = await Task.detached {
                         do {
                             try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                             
                             if FileManager.default.fileExists(atPath: destURL.path) {
                                 try FileManager.default.removeItem(at: destURL)
                             }
                             
                             if encrypted {
                                 try CryptoManager.shared.decryptFile(source: sourceURL, dest: destURL)
                             } else {
                                 try FileManager.default.moveItem(at: sourceURL, to: destURL)
                             }
                             
                             return true
                         } catch {
                             print("💥 Processing Error for \(path): \(error)")
                             
                             if FileManager.default.fileExists(atPath: destURL.path) {
                                 try? FileManager.default.removeItem(at: destURL)
                                 print("🗑️  Removed corrupt file: \(destURL.lastPathComponent)")
                             }
                             
                             return false
                         }
                     }.value
                     
                     try? FileManager.default.removeItem(at: url)
                     
                     if success {
                         successCount += 1
                     } else {
                         failCount += 1
                     }
                     
                 case .failure:
                     failCount += 1
                 }
             }
        }
        
        await MainActor.run {
            self.isRestoring = false
            let message = "Restored \(successCount) files." + (failCount > 0 ? " (\(failCount) failed)" : "")
            NotificationManager.shared.send(title: "Restore Complete", body: message, type: .backupComplete)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destination.path)
        }
    }
}

struct FileRow: View {
    let item: FileItem
    let isSelected: Bool
    let onTap: () -> Void
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            Image(systemName: item.isFolder ? "folder.fill" : "doc.text")
                .foregroundColor(item.isFolder ? .blue : .secondary)
            
            Text(item.name)
                .foregroundColor(.primary)
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .padding(.vertical, 2)
    }
}
