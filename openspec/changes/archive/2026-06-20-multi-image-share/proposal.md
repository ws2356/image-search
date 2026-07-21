## Why

The mobile-to-PC instant share flow currently supports sharing only a single image (or single text) per session. Users can select multiple images in the iOS Share Sheet, but the payload extractor returns immediately after the first match — discarding all subsequent items. This forces users to share images one at a time, which is slow and frustrating. The system must support selecting and sharing multiple images in a single instant share session.

## What Changes

- **BREAKING**: `InstantSharePayloadEnvelope` on iOS changes from a single-item envelope to an array-based collection
- Add a new `PayloadClass.BATCH` to both iOS (`InstantSharePayloadClass`) and PC (`PayloadClass`) enums — or alternatively treat multi-image as multiple sequential `/transfer/image` calls within the same session
- Update `InstantSharePayloadExtractor.extract()` to collect ALL matching image providers instead of returning on first match
- Update `InstantShareExtensionViewModel` to store and send multiple payloads
- Update `InstantShareUploadClient` to upload images sequentially (or concurrently) within the same session, with per-image progress tracking
- Add a total image count to the trust confirm metadata so the PC knows how many images to expect
- Update the mini-window UI to show multi-item progress (e.g., "Receiving 3 of 5 images...")
- PC-side transfer handler and delivery service already support receiving one image per request — reuse this by keeping `/transfer/image` per-image but adding batch session context
- No changes to the trust handshake protocol itself (DH exchange, PIN, cert exchange remain the same)

## Capabilities

### New Capabilities
- `multi-image-payload-ios`: iOS payload extraction collects all selected images into a batch, ViewModel manages a list of payloads, and upload client sends them sequentially within one session with aggregate progress tracking.
- `multi-image-session-pc`: PC session lifecycle and mini-window display updated to track multi-item transfer progress (count of images, per-image delivery status) within a single session.

### Modified Capabilities
- `instant-share-secure-discovery-trust`: Trust confirm metadata includes `image_count` so the PC knows the expected batch size. The `/transfer/image` endpoint is called multiple times within the same session.
- `pc-revisit-session`: Revisit session metadata includes `image_count` for batch transfers. Delivery completes only after all images are received.

## Impact

- **iOS code**: `InstantSharePayloadExtractor.swift` (extraction logic), `InstantShareExtensionViewModel.swift` (multiple payloads, send loop), `InstantShareService.swift` (multi-image storage), `InstantShareUploadClient.swift` (sequential uploads), `InstantShareServices.swift` (enum updates)
- **PC code**: `contracts.py` (PayloadClass enum), `transfer_server.py` (batch-aware receive), `orchestrator.py` (multi-item lifecycle events), `mini_window.py` (multi-item progress UI), `https_tls_server.py` (unchanged per-image endpoint, reused)
- **Specs updated**: `instant-share-secure-discovery-trust`, `pc-revisit-session`
