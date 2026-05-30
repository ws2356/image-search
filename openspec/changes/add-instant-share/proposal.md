## Why

Users currently need to launch AuSearch or AuBackup and navigate through multiple steps to move content from iPhone to PC. This adds friction for quick, one-off sharing scenarios where users expect a "share and forget" flow directly from iOS Share Extension.

## What Changes

- Add an iPhone Share Extension driven "Instant Share" flow that supports text, screenshots, photos, and videos from iOS share sheet.
- Add BLE-based candidate PC discovery before send, so mobile scans pairing-service broadcasts and shows a list of available PCs for user selection.
- Add a first-share trust establishment flow: after user selects a PC, mobile and PC perform DH exchange, receiver shows a PIN popup, sender shows same PIN for user confirmation, then both sides exchange X509 public certificates.
- Add HTTPS transport with self-signed certs after first trust establishment, using exchanged certificates during TLS negotiation.
- Add signed PC broadcasts and public-key pinning for future sharing so mobile can verify signature and send directly to trusted PC over HTTPS.
- Add configurable receive targets on PC:
  - clipboard for text/image payloads
  - local file save for image/video payloads
- Add a fast, minimal confirmation and status UX on both sides to show queued, transferring, success, and failure outcomes.
- Add fallback behavior when PC is unreachable (retry/backoff and user-visible error state).
- Defer large media optimization (special handling for very large payloads) to a future iteration.
- Keep Instant Share implementation separate from mobile-folder implementation: reuse `dt_image_search/mobile/*` only when code is directly reusable without changes; place PC-side implementation in `dt_image_search/instant_sharing`.

## Capabilities

### New Capabilities
- `instant-share-ingest`: Accept and normalize iOS Share Extension payloads (text/image/video) for transfer.
- `instant-share-auto-receive`: Detect incoming instant-share sessions and automatically activate a focused receive UX in AuSearch/AuBackup on PC.
- `instant-share-target-delivery`: Deliver received payloads to clipboard (text/image) or local files (image/video) with deterministic naming and success feedback.
- `instant-share-secure-discovery-trust`: Discover candidate PCs over BLE, establish trust with PIN-verified DH plus X509 public certificate exchange, and enable signed-broadcast/cert-pinned direct HTTPS sharing for future sends.
- `instant-share-transfer-reliability`: Provide connection negotiation, retry policy, timeout handling, and final result states for a quick-share workflow.

### Modified Capabilities
- None.

## Impact

- Affected systems:
  - iOS companion app: Share Extension entrypoint, payload extraction, transfer trigger
  - mobile/pc transport path: BLE discovery, trust handshake, payload transfer protocol
  - PC app UX (AuSearch/AuBackup): auto-activation surface and completion feedback
- Affected code areas (expected):
  - `mobile/ios/*` share/transfer and state handling
  - `dt_image_search/mobile/*` capability exchange/session code (reuse only when directly reusable without changes)
  - `dt_image_search/instant_sharing/*` new PC-side orchestration, trust, transport, and delivery code
  - PC UI controllers and event bus integration for auto-receive UX
- Potential dependency/API impacts:
  - Additional transport metadata for content type, target(s), trust state, and pinned-cert identity
  - BLE broadcast payload/signature format and verification keys
  - HTTPS self-signed certificate trust path with public key pinning
  - Clipboard/file-write permissions and path validation on desktop
