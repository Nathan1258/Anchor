# Anchor
![Logo](https://is5-ssl.mzstatic.com/image/thumb/Purple123/v4/22/05/fd/2205fd56-f4fd-9ceb-4280-e5eb798cf9d0/AppIcon-85-220-0-4-2x.png/240x0w.webp)

**Anchor** is a powerful, lightweight open-source backup utility for macOS that provides a "Safety Net" for your iCloud Drive and Photo Library. It monitors your files in real-time and securely vaults them to a local drive or S3-compatible cloud storage.

While iCloud is great for syncing, it isn't a true backup—if you delete a file accidentally, it's often gone across all devices. Anchor bridges this gap by maintaining a secondary, independent copy of your data, complete with optional **AES-256 zero-knowledge encryption**.

---

## Features

* **Dual-Engine Sync:** Simultaneous monitoring of both your iCloud Drive and your System Photo Library.
* **Smart Scanning:** Uses Generation IDs to track file changes efficiently without constant, heavy re-uploads.
* **Hybrid Storage:** Back up to a local external HDD/SSD or any S3-compatible provider (AWS, Cloudflare R2, Backblaze B2, MinIO).
* **Zero-Knowledge Encryption:** Secure your vault with a master password. Your files are encrypted locally before they ever leave your Mac.
* **Native Experience:** Built entirely in Swift and SwiftUI, living right in your Menu Bar for quick status updates.
* **Restore Browser:** A built-in file explorer to browse your vault and selectively restore files or folders.

**Anchor requires **Full Disk Access** and **Photos Library** permissions to function correctly. If the app remains in "Waiting for Vault" or "Access Denied" status, please check your settings in **System Settings > Privacy & Security**.**

---

## Installation
Anchor is available through two channels to suit different user needs:

### Mac App Store (Recommended)
For the most seamless experience, you can [download Anchor on the Mac App Store](https://apps.apple.com/gb/app/anchor/id6758733462). This version includes:

* Automated updates through the App Store.
* Sandboxed and notarized by Apple for your peace of mind.
* Helps fund the continued development of the project!

### Open Source (Build from Source)

If you prefer to manage the software yourself, Anchor is fully open source. You can download the source code here on GitHub to audit the logic or build the project on your own Mac using Xcode:

1. Clone the repository: git clone https://github.com/Nathan1258/Anchor.git
2. Open Anchor.xcodeproj in Xcode 15+.
3. Build and run using your own Developer ID.

Note: Building from source requires an Apple Developer account and basic knowledge of Xcode.

---

## Contributing

Contributions are always welcome!

Whether it's fixing a bug in the S3 multipart upload logic or improving the UI, your help is appreciated. See `contributing.md` for ways to get started.

Please adhere to this project's `code of conduct`.

---
