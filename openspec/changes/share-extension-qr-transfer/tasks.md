## 1. Launch Agent: Stash and Claim Endpoints

- [ ] 1.1 Add `QRTransferHandler` class with in-memory stash registry (stash_id, content, content_type, filename, opt_code, expiry, attempt_count)
- [ ] 1.2 Implement `POST /api/qr-transfer/v1/stash` handler — accept text/image from localhost, generate stash_id, return 201
- [ ] 1.3 Implement opt-code generation (6-digit CSPRNG, 5-min TTL, 3-attempt invalidation)
- [ ] 1.4 Implement `POST /api/qr-transfer/v1/claim` handler — validate opt-code, return stored payload, invalidate stash on success or 3 failed attempts
- [ ] 1.5 Implement background cleanup timer for expired stashes
- [ ] 1.6 Add 50 MB payload size limit check to stash handler
- [ ] 1.7 Register new endpoints (prefix `/api/qr-transfer/v1/`) in `InstantShareHTTPServer` alongside existing v1 endpoints
- [ ] 1.8 Add unit tests for stash/claim/opt-code/expiry logic

## 2. Launch Agent: QR Display Mini-Window

- [ ] 2.1 Create `QRTransferMiniWindow` Qt dialog (based on `InstantShareMiniWindow` pattern) with QR code display, opt-code text fallback, PC name, and "Scan with AuBackup" instruction
- [ ] 2.2 Integrate QR code generation using existing `qrcode` library — encode `ausearch://claim?ips=...&port=9527&stash=<id>&opt=<code>`
- [ ] 2.3 Wire QR window lifecycle: show on stash, invalidate on cancel, update on claim/expiry, auto-close
- [ ] 2.4 Add LAN IP discovery utility to populate the QR with the PC's LAN IP addresses
- [ ] 2.5 Wire the QR transfer flow into `InstantShareRuntime` as an alternative receive mode (triggered by stash endpoint, not by mDNS/BLE)

## 3. iOS AuBackup: QR Download Client

- [ ] 3.1 Create `QRTransferDownloadClient` Swift class with `claim(host:port:stashId:optCode:completion:)` method
- [ ] 3.2 Implement claim response handling: parse `Content-Type` header, extract text data or image data
- [ ] 3.3 Handle failover — iterate through IP list from QR code on connection failure
- [ ] 3.4 Handle all error responses (401, 410, 404, 5xx) with user-visible error strings
- [ ] 3.5 Register `aubackup://qr-claim` URL scheme handling in `AlbumTransporterApp`
- [ ] 3.6 Update existing `LiveQRCodeScannerView` to detect `ausearch://claim?` format and route to claim flow
- [ ] 3.7 Create `QRTransferResultView` SwiftUI view — text mode (scrollable text + "Copy to Clipboard") and image mode ("Save to Photo Library")
- [ ] 3.8 Add pasteboard copy for text and photo library save for image (with permission handling)
- [ ] 3.9 Add unit tests for `QRTransferDownloadClient`

## 4. macOS Share Extension

- [ ] 4.1 Create `macOSShareExtension` target in PyInstaller spec or Xcode project with `com.apple.share-services` extension point
- [ ] 4.2 Create `MacShareViewController.swift` — receive text/file from `NSExtensionItem`, extract payload
- [ ] 4.3 Implement HTTP POST to `http://127.0.0.1:9527/api/qr-transfer/v1/stash` with text or image payload
- [ ] 4.4 Create confirmation UI (SwiftUI or AppKit) — "Data sent. Open AuBackup on your iPhone and scan the QR code on your Mac."
- [ ] 4.5 Configure `NSExtensionActivationRule` for text and file URL types only
- [ ] 4.6 Add sandbox entitlements (`com.apple.security.network.local`, `com.apple.security.network.client`)

## 5. Build & Integration

- [ ] 5.1 Update `DTImageSearch.spec` (PyInstaller) to include the Share Extension bundle in the app package
- [ ] 5.2 Update `InstantShareRuntime.start()` to initialize `QRTransferHandler` and register QR transfer routes
- [ ] 5.3 Update Launch Agent plist if any new entitlements or code signing changes are needed
- [ ] 5.4 Add the new Swift files to the iOS Xcode project (AlbumTransporterKit target)
- [ ] 5.5 Update `mobile/ios/AlbumTransporterApp.xcodeproj` to include the QR transfer views and client

## 6. Verification

- [ ] 6.1 Test end-to-end flow: share text from macOS → scan QR with iOS → copy to clipboard on iOS
- [ ] 6.2 Test end-to-end flow: share image from macOS → scan QR with iOS → save to photo library on iOS
- [ ] 6.3 Test error cases: invalid opt-code, expired stash, oversized payload, Launch Agent unreachable
- [ ] 6.4 Test concurrent flow: second stash while first is pending (single-user mode — second replaces or shows busy)
