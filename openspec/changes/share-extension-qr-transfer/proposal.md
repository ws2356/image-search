## Why

Users frequently need to quickly share a file or text from their Mac to their iPhone without emailing, AirDropping, or messaging themselves. Current flow requires manual work — save file, open messaging app, send to self, save on phone. A seamless Mac-to-iPhone share via QR code eliminates this friction by leveraging the existing AuSearch Launch Agent and AuBackup iOS app infrastructure.

## What Changes

- **New**: macOS Share Extension that appears in the system share menu for files and text
- **New**: Launch Agent QR code display — when the share extension sends data, the Launch Agent pops a mini window showing a QR code encoding PC IPs + an opt code
- **New**: AuBackup iOS QR download flow — scan QR from AuBackup, download data from the Launch Agent's HTTP server, present text or save image to photo library
- **New**: `POST /transfer/qr-claim` endpoint on the Launch Agent HTTP server to serve stashed payloads
- **Modified**: Launch Agent needs a new route handler and QR generation + mini-window display capability

## Capabilities

### New Capabilities
- `macos-share-extension`: macOS Share Extension that accepts shared files/text, sends payload to Launch Agent HTTP endpoint, and confirms delivery
- `launch-agent-qr-display`: Launch Agent receives payload, generates QR encoding PC IPs + opt code, displays mini-window with QR, and serves the payload via a claim endpoint
- `ios-qr-download-client`: AuBackup iOS app scans QR, resolves PC address, performs opt-code handshake, downloads payload, and presents text or saves image to photo library

### Modified Capabilities
<!-- No existing spec-level capabilities are being modified — all capabilities are new -->

## Impact

- **New target**: macOS Share Extension (AppKit, `NSSharingService` provider) inside the AuSearch app bundle
- **New/modified**: `dt_image_search/instant_sharing/` — new QR claim endpoint handler, QR generation integration
- **New/modified**: `dt_image_search/instant_sharing/mini_window.py` — QR display window
- **New**: `mobile/ios/Sources/AlbumTransporterKit/Services/` — QR download client service
- **New/modified**: `mobile/ios/Sources/AlbumTransporterKit/Views/` — QR scan + download result UI
- **Dependencies**: `qrcode` Python library (already used for pairing), new `pyobjc` dependency may be needed for Share Extension
