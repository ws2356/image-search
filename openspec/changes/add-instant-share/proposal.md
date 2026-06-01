## Why

Users currently need to launch AuSearch or AuBackup and navigate through multiple steps to move content from iPhone to PC. This adds friction for quick, one-off sharing scenarios where users expect a "share and forget" flow directly from iOS Share Extension.

## What Changes

- Add an iPhone Share Extension driven "Instant Share" flow that supports text and images from iOS share sheet in the current implementation slice, with video and other file types deferred to follow-up work.
- Add BLE-based candidate PC discovery before send, so mobile scans pairing-service broadcasts and shows a list of available PCs for user selection.
- Add a desktop background daemon process that continuously broadcasts instant-sharing BLE service for mobile discovery and access, independent of backup session state.
- Add a first-share trust establishment flow: after user selects a PC, mobile and PC perform DH exchange, receiver shows a PIN popup, sender shows same PIN for user confirmation, then both sides exchange X509 public certificates.
- Add HTTPS transport with self-signed certs after first trust establishment, using exchanged certificates during TLS negotiation.
- Add signed PC broadcasts and public-key pinning for future sharing so mobile can verify signature and send directly to trusted PC over HTTPS.
- Add receive-target rules on PC for the current implementation slice:
  - text payloads: clipboard only
  - image payloads: clipboard or local file save
  - video and other file payload rules remain follow-up work
- Desktop instant-sharing receive UX remains unfinalized for v1 implementation lock:
  - option A: full notification-only receive UX
  - option B: notification entry opens AuSearch for instant-sharing receive handling
  - provide two mock sets and finalize UX after review
- Phase UI delivery on both platforms:
  - phase 1: minimum viable UX to get end-to-end instant-share flow running quickly
  - phase 2: dedicated UI design and polish pass after flow validation
- Add a fast confirmation and status UX on both sides to show queued, transferring, success, failure, and user-aborted outcomes in phase 1.
- Add fallback behavior when PC is unreachable (retry/backoff and user-visible error state).
- Defer large media optimization (special handling for very large payloads) to a future iteration.
- Do not reuse existing QR backup pairing/session infrastructure or backup-session capability exchange endpoint for Instant Share flow.
- Keep Instant Share implementation separate from mobile-folder implementation: do not change desktop code in `dt_image_search/mobile/*`; place PC-side implementation in `dt_image_search/instant_sharing`.
- Keep the v1 desktop transfer direction explicit: iOS hosts the local HTTP service and PC acts as the client that completes trust, then downloads the shared text or image.

## Capabilities

### New Capabilities
- `instant-share-ingest`: Accept and normalize iOS Share Extension payloads (text/image/video/other files) for transfer.
- `instant-share-auto-receive`: Detect incoming instant-share sessions and support UX-finalization workflow across two candidate desktop receive patterns before implementation lock.
- `instant-share-target-delivery`: Deliver received payloads using target rules (text to clipboard only, images to clipboard or local files, video/other files to local files) with deterministic naming and success feedback.
- `instant-share-secure-discovery-trust`: Discover candidate PCs over BLE, establish trust with PIN-verified DH plus X509 public certificate exchange, and enable signed-broadcast/cert-pinned direct HTTPS sharing for future sends.
- `instant-share-transfer-reliability`: Provide connection negotiation, retry policy, single-session execution, user-controlled abort/wait behavior, and final result states for a quick-share workflow.

### Modified Capabilities
- None.

## Impact

- Affected systems:
  - iOS companion app: Share Extension entrypoint, payload extraction, transfer trigger
  - mobile/pc transport path: BLE discovery, trust handshake, instant-share-specific payload transfer protocol
  - desktop BLE service daemon: always-on instant-share discovery broadcast
  - PC app UX (AuSearch/AuBackup): notification-based receive surface and completion feedback
  - mobile and PC UI layers: phased MVP-first UI plus later polish pass
- Affected code areas (expected):
  - `mobile/ios/*` share/transfer and state handling
  - New instant-share transport/pairing code path on mobile side (separate from backup-session capability exchange)
  - `dt_image_search/instant_sharing/*` new PC-side orchestration, trust, transport, and delivery code
  - PC UI controllers and event bus integration for candidate receive UX patterns (notification-only vs notification-click-opens-AuSearch)
- Potential dependency/API impacts:
  - Additional transport metadata for content type, allowed target(s), trust state, and pinned-cert identity
  - BLE broadcast payload/signature format and verification keys
  - HTTPS self-signed certificate trust path with public key pinning
  - Clipboard/file-write permissions and path validation on desktop (default save path: user Downloads folder)
