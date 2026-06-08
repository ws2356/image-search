# Spec: Universal Link Trigger for PC-to-Mobile Instant Share

## Objective
Replace the custom `ausearch://` URI scheme with universal links (`https://dl.boldman.net/share?...`) for the PC-to-mobile instant share (QR claim) flow. Universal links are more reliable on iOS — they work when tapped from any context without the "Open in app?" confirmation dialog that custom schemes require.

## Scope
- **iOS only** — PC-side QR URL generation is out of scope (separate task)
- **Replace entirely** — remove `ausearch://` support from iOS, keep only universal link handling

## URL Format
```
https://dl.boldman.net/share?ips=<ip1>,<ip2>&port=<port>&stash=<stashId>&opt=<optCode>
```
Query parameters are identical to the current `ausearch://claim?...` format.

## Changes

### 1. `MobileAppDomain.swift` — Update `QRClaimPayload`
- Change URL parsing to accept `https://dl.boldman.net/share?...` format
- Remove `ausearch://claim?` and `aubackup://qr-claim?` parsing branches
- Extract `ips`, `port`, `stash`, `opt` from universal link query parameters

### 2. `AlbumTransporterRootView.swift` — Update URL handlers
- `onOpenURL`: Remove `aubackup://qr-claim` handling (custom scheme no longer used)
- `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`: Add parsing for `/share` path → extract `QRClaimPayload` → call `model.onQRClaimScanned()`

### 3. `MobileAppModel.swift` — Update `handleIncomingUniversalLink`
- Add `/share` path recognition alongside existing pairing link handling
- Route `/share` links to `onQRClaimScanned()` instead of pairing flow

### 4. `Info.plist` — Remove custom URL scheme
- Remove `CFBundleURLTypes` entry for `aubackup` scheme

## Out of Scope
- PC-side changes to generate universal link URLs
- AASA file updates (already matches `*` paths on `dl.boldman.net`)

## Success Criteria
- Tapping a `https://dl.boldman.net/share?...` universal link opens the AuBackup app and triggers the claim flow
- The app correctly parses `ips`, `port`, `stash`, `opt` from the universal link
- The old `ausearch://claim?...` scheme is no longer handled
- All existing tests pass
