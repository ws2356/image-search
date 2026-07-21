## 1. iOS: Payload Extraction

- [x] 1.1 Change `InstantSharePayloadExtractor.extract()` return type from `InstantSharePayloadEnvelope` to `[InstantSharePayloadEnvelope]`
- [x] 1.2 Modify extraction loop to collect all matching image providers instead of returning on first match
- [x] 1.3 Enforce max batch size (default 10) in extraction; throw error if exceeded
- [x] 1.4 Unit tests for multi-image extraction (2 images, 5 images, mixed types, empty)

## 2. iOS: ViewModel & Service

- [x] 2.1 Change `InstantShareExtensionViewModel.payloadEnvelope` from `InstantSharePayloadEnvelope?` to `[InstantSharePayloadEnvelope] = []`
- [x] 2.2 Update `loadPayload()` to store array from extractor
- [x] 2.3 Update `send()` to loop over all image payloads, calling `uploadImage` sequentially
- [x] 2.4 Add `totalImageCount` computed property, publish batch progress state
- [x] 2.5 Update `InstantShareService` to store `[SharedImageItem]` instead of single `sharedImage`

## 3. iOS: Upload Client

- [x] 3.1 Add `uploadImages(_ urls: [(fileURL: URL, filename: String, contentType: String)]) async throws` method
- [x] 3.2 Method iterates sequentially, calling existing `uploadImage` for each URL with same session
- [x] 3.3 Add `X-Image-Count` headers for PC-side tracking
- [x] 3.4 Aggregate progress across batch (e.g., 3 of 5 complete)

## 4. iOS: Transfer Headers for Batch Metadata

- [x] 4.1 Add `X-Image-Count` header to each `/transfer/image` request (no `X-Image-Index` — no ordering guarantee)
- [x] 4.2 Set `X-Image-Count` to total batch size

## 5. iOS: Unit Tests

- [x] 5.1 Update existing extraction tests for array return type
- [x] 5.2 Add tests for multi-image batch upload (mock URLSession)
- [x] 5.3 Add tests for ViewModel batch state
- [x] 5.4 Run `mobile/ios/scripts/run_unit_tests.sh`

## 6. PC: Contracts & Errors

- [x] 6.1 Add `TRANSFER_LIMIT_EXCEEDED` to `ErrorCode` enum in `contracts.py`
- [x] 6.2 Add `image_count` and `received_count` fields to session metadata/connection config (or store on session state)

## 7. PC: Session & Orchestrator

- [x] 7.1 Add `image_count: int` and `received_count: int` fields to `InstantShareSession` (or session metadata)
- [x] 7.2 Update `handle_transfer_received()` to increment `received_count` and NOT transition to `DELIVERING` if `received_count < image_count`
- [x] 7.3 Update `handle_delivery_complete()` to be called only after `received_count >= image_count`
- [x] 7.4 Update lifecycle events to include `image_count` and `received_count`
- [x] 7.5 Add batch tracking to revisit session creation in `handle_revisit_transfer()`

## 8. PC: Transfer Server

- [x] 8.1 In `https_tls_server.py` transfer handlers, extract `X-Image-Count` header
- [x] 8.2 In `_do_transfer_image`, set `image_count` on session from header (first request only), increment `received_count`
- [x] 8.3 Update `TransferHandler.receive_image()` to accept `image_count` and `received_count` for session tracking

## 9. PC: Mini-Window UI

- [x] 9.1 Update `InstantShareMiniWindow` to display batch progress when `image_count > 1`
- [x] 9.2 Add `image_count` and `received_count` to `MiniWindowState`
- [x] 9.3 Update `_phase_message()` for batch text (e.g., "Receiving image 3 of 5...")
- [x] 9.4 Update progress bar to show batched progress (percentage = received / image_count)

## 10. PC: Unit Tests

- [x] 10.1 Add tests for session batch tracking (image_count, received_count)
- [x] 10.2 Add tests for orchestrator batch lifecycle (no DELIVERING until all received)
- [x] 10.3 Add tests for `TRANSFER_LIMIT_EXCEEDED` error
- [x] 10.4 Run `python -m pytest` on instant_sharing tests
