## 1. macOS Share Extension (Native Swift)

- [x] 1.1 Create `macOSShareExtension` native Swift target in Xcode with `com.apple.share-services` extension point
- [x] 1.2 Create `MacShareViewController.swift` — receive text/file from `NSExtensionItem`, extract payload
- [x] 1.3 Implement HTTP POST over Unix domain socket to `http://localhost/api/instant-share/v1/qr-trigger` — send JSON `{type: "text", content: "..."}` or `{type: "image", file_path: "...", filename: "..."}`
- [x] 1.4 Extension shows no UI of its own — it stashes the payload and exits; the Launch Agent owns all user-facing UI
- [x] 1.5 Configure `NSExtensionActivationRule` for text and file URL types only
- [x] 1.6 Create `ShareExtension.entitlements` file with `com.apple.security.app-sandbox` (true) and `com.apple.security.application-groups` (array containing the app group ID) and check it into the repo
- [x] 1.7 Create `build_share_extension.sh` script that uses `swift build` to compile the Swift extension target and produce `ShareExtension.appex`
- [x] 1.8 Update `build_pyinstaller.sh` to call `build_share_extension.sh` before PyInstaller, then copy the built `.appex` into `Contents/PlugIns/ShareExtension.appex` within the AuSearch bundle
- [x] 1.9 Update `codesign_app.sh` to codesign `Contents/PlugIns/ShareExtension.appex` with `--entitlements ShareExtension.entitlements`
- [ ] 1.10 Update `build_pkg.sh` / `package_dmg.sh` to include and sign `Contents/PlugIns/ShareExtension.appex` in the distribution package
- [ ] 1.11 Update `create_distributable_pkg.sh` to ensure the extension is included in the PKG installer

## 2. Launch Agent: Unix Socket + QR Trigger Endpoints

- [ ] 2.1 Determine extension's sandbox container path from bundle ID; create Unix domain socket listener inside the extension's sandbox container at `~/Library/Containers/<bundle-id>/Data/Library/Application Support/au-search/qr-transfer.sock`
- [ ] 2.2 Implement `QRTriggerHandler` class with in-memory stash registry (stash_id, content/file_path, content_type, filename, opt_code, expiry, attempt_count)
- [ ] 2.3 Implement `POST /api/instant-share/v1/qr-trigger` handler on Unix socket — accept JSON `{type: "text", content: "..."}` or `{type: "image", file_path: "...", filename: "..."}`, generate stash_id, return 201
- [ ] 2.4 Implement opt-code generation (6-digit CSPRNG, 5-min TTL, 3-attempt invalidation)
- [ ] 2.5 Implement `POST /api/instant-share/v1/qr-claim` handler on TCP — validate opt-code, return text inline or stream image file, invalidate on success or 3 failed attempts
- [ ] 2.6 Use oneshot timer per stash (5-min TTL) for expiry cleanup instead of periodic loop
- [ ] 2.7 Register new endpoints in both the Unix socket listener and the TCP HTTP server
- [ ] 2.8 Update `InstantShareRuntime.start()` to initialize `QRTriggerHandler`, create Unix socket, and register QR trigger routes
- [ ] 2.9 Add unit tests for stash/claim/opt-code/expiry/file-path handling

## 3. Launch Agent: QR Display Mini-Window

- [ ] 3.1 Create `QRTriggerMiniWindow` Qt dialog (based on `InstantShareMiniWindow` pattern) with QR code display, opt-code text fallback, PC name + port, and "Scan with AuBackup" instruction
- [ ] 3.2 Integrate QR code generation using existing `qrcode` library — encode `ausearch://claim?ips=...&port=9527&stash=<id>&opt=<code>`
- [ ] 3.3 Wire QR window lifecycle: show on stash, invalidate on cancel, update on claim/expiry, auto-close
- [ ] 3.4 Add LAN IP discovery utility to populate the QR with the PC's LAN IP addresses
- [ ] 3.5 Wire the QR trigger flow into `InstantShareRuntime` as an alternative receive mode (triggered by stash endpoint, not by mDNS/BLE)

## 4. iOS AuBackup: QR Download Client

- [ ] 4.1 Create `QRTriggerDownloadClient` Swift class with `claim(host:port:stashId:optCode:completion:)` method calling `POST /api/instant-share/v1/qr-claim`
- [ ] 4.2 Implement claim response handling: parse `Content-Type` header, extract text data or image data
- [ ] 4.3 Handle failover — iterate through IP list from QR code on connection failure
- [ ] 4.4 Handle all error responses (401, 410, 404, 5xx) with user-visible error strings
- [ ] 4.5 Register `aubackup://qr-claim` URL scheme handling in `AlbumTransporterApp` with raw query params (no base64)
- [ ] 4.6 Update existing `LiveQRCodeScannerView` to detect `ausearch://claim?` format and route to claim flow
- [ ] 4.7 Create `QRTransferResultView` SwiftUI view — text mode (scrollable text + "Copy to Clipboard") and image mode (image display + "Save to Photo Library")
- [ ] 4.8 Add pasteboard copy for text and photo library save for image (with permission handling)
- [ ] 4.9 Add the new Swift files to the iOS Xcode project (AlbumTransporterKit target)
- [ ] 4.10 Update `mobile/ios/AlbumTransporterApp.xcodeproj` to include the QR transfer views and client
- [ ] 4.11 Add unit tests for `QRTriggerDownloadClient`

## 5. Verification

- [ ] 5.1 Test end-to-end flow: share text from macOS → scan QR with iOS → copy to clipboard on iOS
- [ ] 5.2 Test end-to-end flow: share image from macOS → scan QR with iOS → save to photo library on iOS
- [ ] 5.3 Test error cases: invalid opt-code, expired stash, source file deleted, Launch Agent unreachable
- [ ] 5.4 Test concurrent flow: second stash while first is pending (single-user mode — second replaces or shows busy)
