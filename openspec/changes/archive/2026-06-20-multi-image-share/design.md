## Context

The mobile-to-PC instant share flow currently handles exactly one payload per session. Every layer — extraction, ViewModel, upload client, PC transfer handler, session lifecycle, and mini-window — is designed for single-item transfer. Multi-image support requires changes at each layer while preserving backward compatibility for single-image and text flows.

## Goals / Non-Goals

**Goals:**
- User can select 2-10 images in Photos app and share them in one session
- Images are uploaded sequentially within the same session (reusing trust and mTLS)
- Mini-window shows batch progress (e.g., "Receiving image 3 of 5...")
- PC delivers each image independently (same Downloads folder behavior as single image)
- Single image and text sharing remain unchanged (no regression)

**Non-Goals:**
- Parallel/concurrent image uploads (sequentially within session is simpler)
- Sharing a mix of text + images in one session (images only for batch)
- Changing the QR-based share flow (pc-to-mobile via QR code — out of scope)
- Changing the delivery behavior for individual images (each image still goes to Downloads/clipboard as configured)
- Video or other media batch support (images only for v1)

## Decisions

### Decision 1: Sequential uploads within one session, not a new batch endpoint
**Choice**: Keep the existing `/transfer/image` endpoint per-image. Call it N times within the same session, with the same `X-Session-Id`. The trust confirm includes `image_count`.

**Rationale**: This avoids creating a new API protocol and reuses the existing streaming upload + temp file handling. The PC already handles multiple `/transfer/image` calls per session in theory (since multi-session support was added). The only change is that the orchestrator shouldn't transition to `DELIVERING` after the first image — it should wait for all expected images.

**Alternative considered**: New `/transfer/images` endpoint accepting multipart. Rejected — adds complexity for no performance gain (sequential uploads are network-bound, not CPU-bound).

### Decision 2: `X-Image-Count` header on `/transfer/image`
**Choice**: The first `/transfer/image` request carries `X-Image-Count` (total images) as an HTTP header. The PC derives the expected count from the first request. No `X-Image-Index` header since user-selected images have no well-defined order.

**Rationale**: Trust confirm is about establishing trust, not transfer metadata. Headers on transfer requests keep the trust protocol clean. The PC learns the batch size from the first image's header and validates subsequent images against that count — simply incrementing `received_count` per request until it reaches `image_count`.

**Alternative considered**: `image_count` in trust confirm encrypted body. Rejected — mixes payload metadata with trust establishment.

### Decision 3: Payload extraction returns array, not single item
**Choice**: `InstantSharePayloadExtractor.extract()` returns `[InstantSharePayloadEnvelope]` instead of `InstantSharePayloadEnvelope`. The extractor collects ALL matching items before returning.

**Rationale**: The current early-return pattern (`return imageEnvelope`) is the root cause of the single-image limitation. Changing to collect-and-return-array requires minimal changes — the NSItemProvider iteration just needs to aggregate instead of returning on first match.

### Decision 4: No new `PayloadClass.BATCH` — reuse `PayloadClass.IMAGE`
**Choice**: Keep `PayloadClass.IMAGE`. Multiple images within a session are indicated by `image_count > 1`, not by a new enum value.

**Rationale**: The trust handshake's bootstrap metadata already carries `payload_class`. Adding a new value would require protocol version negotiation. Since the behavior per-image is identical (receive, deliver to clipboard/file), the session-level count is sufficient. This also means the PC delivery service doesn't need to change — it already handles one image at a time.

### Decision 5: Mini-window batch progress via lifecycle events
**Choice**: Extend the `instant_share.lifecycle` event payload with `image_count` and `received_count`. The mini-window updates its progress display based on these fields.

**Rationale**: The existing lifecycle event system already drives the mini-window. Adding batch count fields is a minimal extension. The mini-window can divide `received_count / image_count` to show progress percentage.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| Batch upload interrupted mid-way (network drop) | Session tracking on PC knows how many were received; mobile can report failure to user; already-received images are kept |
| Mobile sends more images than declared in `image_count` | PC rejects transfers exceeding `image_count` with `TRANSFER_LIMIT_EXCEEDED` |
| Large batches (10+ images) cause long sessions | Enforce a max batch size (e.g., 10) on the iOS side; validate before starting the trust handshake |
| Memory pressure from holding all payload envelopes in ViewModel | Payload envelopes are lightweight (URL + metadata); images stay in Photos until upload time via file URL |

## Open Questions

- **Q1**: Max batch size? → Default to 10. Configurable later.
- **Q2**: Should failed mid-batch images be retried? → No, report error and stop. User can retry the remaining images in a new session.
- **Q3**: Revisit batch — should `X-Image-Count` header work? → Yes, revisited transfers can include this header.
