## Why

Users currently need to launch AuSearch or AuBackup and navigate through multiple steps to move content from iPhone to PC. This adds friction for quick, one-off sharing scenarios where users expect a "share and forget" flow directly from iOS Share Extension.

## What Changes

- Add an iPhone Share Extension driven "Instant Share" flow that supports text and images from iOS share sheet in the current implementation slice, with video and other file types deferred to follow-up work.
- Add a production device selector card in the iOS Share Extension that discovers PCs via mDNS (Bonjour) on the local network and lists discovered PCs for user selection before handoff.
- When the user taps a discovered PC, the Share Extension performs the full trust + transfer flow natively: starts local HTTPS server, sends HTTP bootstrap to PC, displays PIN for trust verification, receives user confirmation, and delivers the payload. No main-app navigation.
- Add a desktop background daemon process that continuously advertises the instant-sharing service via mDNS (Bonjour) for mobile discovery and access, independent of backup session state.
- Add a first-share trust establishment flow: after user selects a PC, mobile and PC perform DH exchange, receiver shows a PIN popup, sender shows same PIN for user confirmation, then both sides exchange X509 public certificates.
- Add HTTPS transport with self-signed certs after first trust establishment, using exchanged certificates during TLS negotiation.
- Add signed PC mDNS TXT record and public-key pinning for future sharing so mobile can verify signature and send directly to trusted PC over HTTPS.
- Add receive-target rules on PC for the current implementation slice:
  - text payloads: clipboard only
  - image payloads: clipboard or local file save
  - video and other file payload rules remain follow-up work
- Desktop instant-sharing receive UX uses a standalone mini window (Variant B selected):
  - notification entry opens a dedicated 360x520px mini window independent from main AuSearch app
  - mini window has its own title bar, traffic lights, and lifecycle
  - completely separate from existing backup, browser, and search features
  - PIN confirmation, progress, device status, and completion all visible in the mini window
- Ship production-quality mobile and desktop UX for instant-share entry, confirmation, progress, success, failure, and user-aborted outcomes as part of the implementation slice.
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
- `instant-share-secure-discovery-trust`: Discover candidate PCs over mDNS (Bonjour), establish trust with PIN-verified DH plus X509 public certificate exchange, and enable signed-advertisement/cert-pinned direct HTTPS sharing for future sends.
- `instant-share-transfer-reliability`: Provide connection negotiation, retry policy, single-session execution, user-controlled abort/wait behavior, and final result states for a quick-share workflow.

### Modified Capabilities
- None.

## Impact

- Affected systems:
  - iOS companion app: Share Extension entrypoint, payload extraction, production device selector card, and AuBackup handoff
  - mobile/pc transport path: mDNS discovery, trust handshake, instant-share-specific payload transfer protocol
  - desktop mDNS advertisement daemon: always-on instant-share discovery via Bonjour service registration
  - PC app UX: standalone mini window for receive flow, independent from main AuSearch window
  - mobile and PC UI layers: production UX surfaces for selection, handoff, progress, result, and failure states
- Affected code areas (expected):
  - `mobile/ios/*` share/transfer and state handling
  - New instant-share mDNS discovery + trust/transfer orchestration on mobile side (separate from backup-session capability exchange)
  - `dt_image_search/instant_sharing/*` new PC-side orchestration, trust, transport, delivery code, and standalone mini window UI
  - PC standalone mini window controllers, event bus integration, and window lifecycle management
- Potential dependency/API impacts:
  - Additional transport metadata for content type, allowed target(s), trust state, and pinned-cert identity
  - mDNS TXT record payload/signature format and verification keys
  - HTTPS self-signed certificate trust path with public key pinning
  - Clipboard/file-write permissions and path validation on desktop (default save path: user Downloads folder)
  - New PC HTTP endpoint for session bootstrap (replaces BLE ConnectionConfig write)
