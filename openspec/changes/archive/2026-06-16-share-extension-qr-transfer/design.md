## Context

The existing Instant Share system allows iOS-to-macOS sharing via Share Extension → mDNS discovery → DH trust handshake → payload upload. This change inverts the direction: **macOS-to-iOS sharing**, triggered from the macOS right-click/share menu.

Current state:
- **Launch Agent** (InstantShareAgent) already runs HTTP (port 9527) and HTTPS/mTLS (port 9528) servers with trust and transfer endpoints
- **iOS AuBackup** already has QR code scanning for backup pairing and a trust client for the mobile-to-pc flow
- **No macOS Share Extension** exists — only an iOS one

The inversion reuses the existing trust handshake + mTLS transfer infrastructure from the mobile-to-pc flow, replacing the insecure `/qr-claim` plaintext opt-code endpoint with the same DH + cert exchange + mTLS pattern.

## Goals / Non-Goals

**Goals:**
- macOS Share Extension (native Swift) that appears in the system share menu for selected files and text
- Share Extension sends payload to the Launch Agent via HTTP over Unix domain socket
- Launch Agent displays a QR code mini-window encoding PC IPs + port + session_id + opt_code
- iOS app scans QR, performs DH trust handshake + opt-code verification + mTLS download
- Security: encrypted trust handshake, device certificate exchange, mTLS transfer; single-use codes with TTL
- Reuse mobile-to-pc trust endpoints (`/trust/handshake`, `/trust/confirm`) for pc-to-mobile flow

**Non-Goals:**
- Not replacing the existing iOS Share Extension (both coexist)
- Not adding mDNS/BLE discovery for this flow (QR replaces discovery)
- Not supporting batch/album transfers (single file or text per share)

## Decisions

### Decision 1: macOS Share Extension via native Swift
(same as before)

### Decision 2: Trust handshake + opt-code (replaces QR-only opt-code)

**Choice**: The pc-to-mobile QR flow now goes through the full trust handshake:
1. iOS → PC (HTTP): `POST /trust/handshake` — DH key exchange, derive session key
2. iOS → PC (HTTP): `POST /trust/confirm` — encrypted opt_code verification + device certificate exchange
3. iOS → PC (HTTPS/mTLS): `POST /transfer/download` — retrieve stashed content over encrypted mTLS channel

The opt_code is verified inside the encrypted `/trust/confirm` envelope (not in plaintext), and `/trust/apply` is skipped (opt_code already known to both sides from QR).

**Rationale**: 
- Reuses the proven DH + certificate pinning + mTLS infrastructure from mobile-to-pc flow
- The opt_code verification is now encrypted (not sent in plaintext over LAN)
- Device certificates are exchanged, enabling trust-on-first-use for future interactions
- The download occurs over HTTPS/mTLS (port 9528), same server that handles mobile-to-pc uploads

**TrustSession.flow_type**: A `TrustFlowType` enum (`MOBILE_TO_PC` vs `PC_TO_MOBILE`) distinguishes the two flows. The `/trust/confirm` handler checks `flow_type` to determine whether to verify `pin_code` (mobile-to-pc) or `opt_code` (pc-to-mobile).

### Decision 3: Pull-based transfer with mTLS (PC hosts, iOS pulls)

**Choice**: The Launch Agent creates a trust session at `/qr-trigger` time (linking session_id → stash_id → opt_code). iOS completes the trust flow, then calls `POST /transfer/download` over HTTPS/mTLS to retrieve the content.

**Rationale**: End-to-end encrypted transfer. The TLS server's mTLS ensures only the authenticated iOS device can download. No plaintext opt-code or content on the wire.

### Decision 4: Endpoint changes

**Removed:** `POST /api/instant-share/v1/qr-claim` — replaced by trust handshake + `/transfer/download`.

**Added:** `POST /api/instant-share/v1/transfer/download` — hosted on HTTPS/mTLS server (port 9528), returns stashed content.

**Modified:**
- `/trust/confirm` now accepts either `pin_code` (mobile-to-pc) or `opt_code` (pc-to-mobile) based on `TrustSession.flow_type`.
- `/qr-trigger` response now includes `session_id` in addition to `stash_id`.

### Decision 5: QR payload format

**Shortened params for minimal QR size:**
- `https://dl.boldman.net/share?ips=...&p=<port>&sid=<session_id>&opt=<opt_code>`
- `p` = port (was `port`), `sid` = session_id (was `stash` for stash_id)
- stash_id is stored inside the trust session on the PC, not exposed in QR

### Decision 6: Unix domain socket + Image file path
(same as before)

## Risks / Trade-offs

- **[Risk] QR staleness**: If the QR is scanned after the trust session expires (5-min TTL), the handshake will fail. **Mitigation**: The opt_code TTL gates the entire flow; expired opt_codes are rejected at `/trust/confirm`.
- **[Risk] Session_id collision**: With UUID session_ids, collision is negligible. **Mitigation**: UUID v4 with CSPRNG.
- **[Risk] iOS app in background**: User may scan QR while iOS app is in background. **Mitigation**: Universal link (`https://dl.boldman.net/share?...`) deep-links into AuBackup.
- **[Risk] mTLS handshake failure**: If the iOS device hasn't stored the PC's certificate (first-time pairing), the mTLS download fails. **Mitigation**: Certificate exchanged during `/trust/confirm`, stored in keychain before download.
