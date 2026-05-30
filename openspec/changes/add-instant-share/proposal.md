## Why

Users currently need to launch AuSearch or AuBackup and navigate through multiple steps to move content from iPhone to PC. This adds friction for quick, one-off sharing scenarios where users expect a "share and forget" flow directly from iOS Share Extension.

## What Changes

- Add an iPhone Share Extension driven "Instant Share" flow that supports text, screenshots, photos, and videos from iOS share sheet.
- Add a lightweight capability handshake between iPhone and PC so the PC app can auto-activate a receiving UX when an instant-share request is initiated.
- Add configurable receive targets on PC:
  - clipboard for text payloads
  - local file drop for image/video payloads
- Add a fast, minimal confirmation and status UX on both sides to show queued, transferring, success, and failure outcomes.
- Add fallback behavior when PC is unreachable (retry/backoff and user-visible error state).

## Capabilities

### New Capabilities
- `instant-share-ingest`: Accept and normalize iOS Share Extension payloads (text/image/video) for transfer.
- `instant-share-auto-receive`: Detect incoming instant-share sessions and automatically activate a focused receive UX in AuSearch/AuBackup on PC.
- `instant-share-target-delivery`: Deliver received payloads to clipboard (text) or local files (image/video) with deterministic naming and success feedback.
- `instant-share-transfer-reliability`: Provide connection negotiation, retry policy, timeout handling, and final result states for a quick-share workflow.

### Modified Capabilities
- None.

## Impact

- Affected systems:
  - iOS companion app: Share Extension entrypoint, payload extraction, transfer trigger
  - mobile/pc transport path: pairing/session handshake, payload transfer protocol
  - PC app UX (AuSearch/AuBackup): auto-activation surface and completion feedback
- Affected code areas (expected):
  - `mobile/ios/*` share/transfer and state handling
  - `dt_image_search/mobile/*` capability exchange/session code
  - PC UI controllers and event bus integration for auto-receive UX
- Potential dependency/API impacts:
  - New extension-safe payload handling for large media
  - Additional transport metadata for content type, target, and receive policy
  - Clipboard/file-write permissions and path validation on desktop
