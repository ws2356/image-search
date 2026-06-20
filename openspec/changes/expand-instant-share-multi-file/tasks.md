## 1. Data Model: Batch File Types

- [ ] 1.1 Add `FileEntry` dataclass to `contracts.py` with fields: `file_path`, `filename`, `content_type`, `size_bytes`
- [ ] 1.2 Extend `StashEntry` in `qr_trigger_handler.py` with optional `files: list[FileEntry]` field; keep legacy `file_path`/`filename` as deprecated but functional
- [ ] 1.3 Update `qr_trigger_handler._create_stash()` to populate `files` list (single entry for legacy flow, multiple for batch)

## 2. PC-Side: QR Trigger Handler Batch Support

- [ ] 2.1 Update `QRTriggerHandler.handle_trigger()` to detect batch format: if `files` key present, iterate and validate each file entry; wrap legacy `file_path` into single-entry `files` list internally
- [ ] 2.2 Add batch file count validation: reject if `len(files) > max_batch_file_count` (default 50, configurable via `instant_share.max_batch_file_count`)
- [ ] 2.3 Add per-file MIME detection for each entry in the batch (reuse existing `_detect_mime`)
- [ ] 2.4 Update `retrieve_stash_content()` to always return a JSON manifest (`file_count` + `files` array) for any stash (single or multi-file). Remove inline file byte return — file bytes are now only served by `/transfer/download/<index>`

## 3. PC-Side: Transfer Manifest + Per-File Download Endpoints

- [ ] 3.1 Rename `/api/instant-share/v1/transfer/download` route to `/api/instant-share/v1/transfer/manifest` in `contracts.py` (`TRANSFER_MANIFEST_PATH`) and `https_tls_server.py`
- [ ] 3.2 Implement `_do_transfer_manifest()` handler: always returns JSON `{file_count, files: [{index, filename, content_type, size_bytes}]}` for any stash size
- [ ] 3.3 Add `/api/instant-share/v1/transfer/download/<file_index>` route to `https_tls_server.py` with `_do_transfer_download_file()` handler: validate `file_index` against stash file count, read file bytes from `stash.files[file_index].file_path`, return with correct `Content-Type` and `X-Original-Filename` headers

## 4. PC-Side: QR Trigger Mini Window Batch UI

- [ ] 4.1 Update `QRTriggerMiniWindow.apply_stash_event()` to accept `file_count` and optional `filenames` list
- [ ] 4.2 Display "Sharing N files from Mac" in mini window main message when `file_count > 1`
- [ ] 4.3 Add scrollable filename list widget; truncate at 10 with "+N more files..." label
- [ ] 4.4 Update `QRTriggerMiniWindowFactory.create_window()` to pass batch metadata to the window

## 5. macOS Share Extension: Multi-File Acceptance

- [ ] 5.1 Update `NSExtensionActivationRule` in `Info.plist` to set `NSExtensionActivationSupportsFileWithMaxCount` to 50 (or configurable value) for `public.file-url`
- [ ] 5.2 Update extension's payload extraction logic to iterate all `NSItemProvider` file URLs and collect into a list
- [ ] 5.3 Update stash POST body: send `{type: "image", files: [{file_path, filename}, ...]}` for multi-file; keep legacy `{type: "image", file_path, filename}` for single file

## 6. iOS Client: Multi-File Download

- [ ] 6.1 Add `MultiFileReceiveView` SwiftUI view with file list (filename, SF Symbol icon, formatted size), per-file "Save" button, and "Save All" button
- [ ] 6.2 Implement manifest-first download flow: always call `POST /transfer/manifest` first to get file listing, then navigate to appropriate receive view (single vs multi-file)
- [ ] 6.3 Implement sequential download manager: use manifest's `files` array to iterate `GET /transfer/download/<index>`, track per-file success/failure, aggregate progress
- [ ] 6.4 Implement per-file save: images → PHPhotoLibrary, other types → Files app (document picker)
- [ ] 6.5 Handle partial failure: skip failed files, show retry option, display summary at end ("X of Y files saved. Z files failed.")
- [ ] 6.6 Handle stash expiry during batch: stop downloads on 410, show expiry message with partial results

## 7. Integration & Validation

- [ ] 7.1 End-to-end test: share 3 files from macOS Finder → QR code appears → scan with iOS → download all 3 → verify saved to Photos
- [ ] 7.2 Backward compatibility test: single-file share from old or new extension → still works with old and new iOS clients
- [ ] 7.3 Batch limit test: attempt to share 51 files → extension/trigger rejects with clear error
- [ ] 7.4 Partial failure test: simulate file deletion mid-download → iOS shows partial results with error
