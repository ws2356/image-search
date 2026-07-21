## Why

The macOS Share Extension currently limits PC-to-mobile instant sharing to a single file. Users frequently select multiple files in Finder and expect to share them all in one operation. Supporting multi-file PC-to-mobile sharing removes a significant UX friction point and aligns the PC-to-mobile flow with the already-existing mobile-to-PC multi-image batch sharing.

## What Changes

- **macOS Share Extension**: Update `NSExtensionActivationRule` to accept multiple file URLs (`public.file-url` with `NSExtensionActivationSupportsFileWithMaxCount > 1`), enabling multi-file selection from Finder.
- **PC-side QR trigger handler**: Extend `StashEntry` and `QRTriggerHandler.handle_trigger` to accept and store multiple file paths in a single batch stash. Generate a single QR code covering the entire batch.
- **PC-side QR trigger mini window**: Show batch count and aggregated filenames when multiple files are stashed.
- **iOS download client**: Support sequential download of multiple files from a single QR claim, with per-file save and aggregated progress.
- **PC-side transfer API**: Rename `/api/instant-share/v1/transfer/download` to `/api/instant-share/v1/transfer/manifest` — this endpoint now always returns a JSON file manifest (not inline bytes). Add `/api/instant-share/v1/transfer/download/<index>` as the universal per-file download endpoint. This manifest-first, download-second pattern applies uniformly to both single-file and multi-file sharing.
- **Batch metadata on the stash**: Track `file_count` and per-file `filename` / `content_type` / `size_bytes` for each file in the batch stash, enabling accurate UI and download coordination.

## Capabilities

### New Capabilities
- `multi-file-qr-stashing`: PC-side QR trigger handler supports creating batch stashes with multiple file paths, tracking per-file metadata (filename, content_type, size) within a single stash entry. A single QR code is generated for the entire batch.
- `multi-file-qr-mini-window`: The QR trigger mini window displays the batch file count and lists individual filenames for multi-file stashes, giving PC users visibility into what will be shared.
- `multi-file-ios-download`: iOS download client handles batch claims — receives a file manifest from the PC, downloads each file sequentially, presents aggregated progress, and allows the user to save each file or save all to Photos/Files.

### Modified Capabilities
- `macos-share-extension`: The `NSExtensionActivationRule` will be changed to accept multiple `public.file-url` items (max count > 1). The extension's payload extraction and stashing logic WILL change to iterate over all received file URLs and send them as a batch to the QR trigger endpoint.

## Impact

- **Affected code**: `dt_image_search/instant_sharing/qr_trigger_handler.py` (StashEntry, handle_trigger), `dt_image_search/instant_sharing/qr_trigger_mini_window.py` (batch UI), `dt_image_search/instant_sharing/qr_trigger_mini_window_factory.py`, `dt_image_search/instant_sharing/contracts.py` (new batch types), `dt_image_search/instant_sharing/https_tls_server.py` (batch download), macOS Share Extension (activation rule, payload extraction), iOS QR download client
- **APIs**: `/api/instant-share/v1/qr-trigger` body schema changes to accept list of files. `/api/instant-share/v1/transfer/download` renamed to `/transfer/manifest` (always returns JSON manifest). New `/api/instant-share/v1/transfer/download/<index>` for per-file download.
- **Dependencies**: None new. Uses existing `InstantShareDeliveryService`, `InstantShareSessionRegistry`, and trust infrastructure.
- **Breaking changes**: **BREAKING** — `/api/instant-share/v1/transfer/download` renamed to `/transfer/manifest` (response type changes from inline bytes to always-JSON manifest). Old iOS clients calling the old endpoint receive 404. Coordinated PC + iOS update required. The `/qr-trigger` request body is backward-compatible: legacy `{type: "image", file_path: "..."}` still works.
