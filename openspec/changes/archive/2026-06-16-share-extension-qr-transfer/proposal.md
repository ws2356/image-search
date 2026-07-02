## Why

Users frequently need to quickly share a file or text from their Mac to their iPhone without emailing, AirDropping, or messaging themselves. Current flow requires manual work — save file, open messaging app, send to self, save on phone. A seamless Mac-to-iPhone share via QR code eliminates this friction by leveraging the existing AuSearch Launch Agent and AuBackup iOS app infrastructure.

## What Changes

- **New**: macOS Share Extension that appears in the system share menu for files and text
- **New**: Launch Agent receives the shared data and displays a QR code — the iOS app scans the QR and downloads the data
- **New**: AuBackup iOS QR download flow — scans QR, downloads data from the Launch Agent, presents text or saves image to photo library

## Capabilities

### New Capabilities
- `macos-share-extension`: macOS Share Extension that accepts shared files/text and sends them to the Launch Agent
- `launch-agent-qr-display`: Launch Agent receives payload, generates QR encoding PC connection info + opt code, displays mini-window with QR, and serves the payload via a claim endpoint
- `ios-qr-download-client`: AuBackup iOS app scans QR, resolves PC address, performs opt-code handshake, downloads payload, and presents text or saves image to photo library

### Modified Capabilities
<!-- No existing spec-level capabilities are being modified — all capabilities are new -->

## Impact

- **New target**: macOS Share Extension bundled inside the AuSearch app
- **New/modified**: `dt_image_search/instant_sharing/` — new QR trigger endpoint handler, Unix socket listener, QR generation
- **New/modified**: `dt_image_search/instant_sharing/mini_window.py` — QR display window
- **New**: `mobile/ios/Sources/AlbumTransporterKit/Services/` — QR download client service
- **New/modified**: `mobile/ios/Sources/AlbumTransporterKit/Views/` — QR scan + download result UI
