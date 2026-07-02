## Context

The instant-share system already supports trust establishment between mobile (iOS) and PC via a three-step handshake (DH exchange → encrypted PIN → certificate exchange). After first trust, both sides persist each other's X.509 certificates. However, currently every share repeats the full handshake — the persisted certificates are unused for skipping re-authentication.

The key insight: **mTLS already proves identity.** The TLS handshake verifies both the server's certificate (mobile authenticates the PC) and the client's certificate (PC authenticates the mobile). If both sides have each other's certs from a previous trust exchange, the mTLS handshake alone is sufficient proof — no additional Ed25519 signature verification over mDNS TXT records is needed.

The PC side already loads trusted peer certs into the mTLS CA bundle (`load_all_peer_certificates()` at server start + dynamic injection via `add_peer_certificate()` after trust confirm). When an untrusted client connects, the TLS handshake fails at the SSL layer (before any HTTP exchange) — there is no 403 response, the connection is simply refused.

## Goals / Non-Goals

**Goals:**
- Mobile attempts direct mTLS transfer to `/transfer/xxx` for any discovered PC — the TLS handshake itself determines whether this is a revisit or requires the full trust flow
- PC-side TLS transfer endpoints accept requests from trusted mTLS peers without a prior trust session (on-the-fly session creation)
- If the TLS handshake fails (PC doesn't trust the mobile's cert, or mobile doesn't trust the PC's cert), mobile falls back to the full trust handshake
- Mobile sends `peerDeviceName` so the PC can display which device is sharing

**Non-Goals:**
- Changing the mDNS TXT record format
- Replacing the existing first-share trust handshake flow (it remains as the fallback)
- BLE-based revisit (BLE provides connectivity discovery only, same as mDNS)
- Certificate revocation or expiry notification mechanisms
- Supporting multiple concurrent sessions (later sessions override existing ones for now)

## Decisions

### Decision 1: Identity from TLS certificate CN, not mDNS TXT

mDNS provides connectivity only (hostname/IP + `tls_port`). Device identity is derived from the TLS certificate CN during the mTLS handshake:

- **Mobile side**: The PC's certificate CN *is* its `device_id` (set during cert generation in `device_identity.py:334`). The mobile already extracts the CN via `CertTools.swift` during the mTLS handshake (`SecCertificateCopyCommonName`). This replaces deriving `device_id` from mDNS TXT records.
- **PC side**: No changes needed. The TLS server already validates client certs against the CA bundle (all trusted peer certs loaded at startup + dynamically injected after trust confirm). The TLS handshake succeeding is itself the trust proof — the framework (OpenSSL) handles all cert validation.

This eliminates the need for Ed25519 signature verification over mDNS TXT records entirely.

### Decision 2: Revisit = blind mTLS transfer attempt

When the mobile discovers a PC via mDNS, it attempts a direct mTLS transfer without pre-checking whether stored certs exist:
1. Connects to `tls_port` (from mDNS) via HTTPS with its own X.509 client certificate
2. Sets `X-Session-Id` (UUID v4) and `X-Peer-Device-Name` headers
3. POSTs payload to `/transfer/text` or `/transfer/image` directly

The TLS handshake itself determines the outcome:
- **Success**: Both sides' certs are mutually trusted → transfer proceeds. The mobile's `InstantShareServerTrustDelegate` already validates the PC's cert during the TLS handshake.
- **Failure**: TLS handshake fails at the SSL layer (either side rejects the other's cert) → connection refused → mobile falls back to the full trust handshake.

No `/trust/handshake`, `/trust/apply`, or `/trust/confirm` calls are made. The mTLS handshake itself authenticates both sides. No separate cert-existence check is needed — just connect and let TLS decide.

### Decision 3: Fallback triggered by TLS handshake failure

When the mobile's client cert is not in the PC's CA bundle, the TLS handshake fails at the SSL layer — the connection is refused, and the PC never receives an HTTP request. The mobile detects this as a connection/TLS error and falls back to the full trust handshake.

There are two failure modes:
1. **TLS handshake failure** (cert not trusted) → connection refused → mobile falls back to trust handshake
2. **Application-layer conflict** (e.g., another session active) → PC returns 409/RECEIVER_BUSY → mobile retries or falls back

### Decision 4: PC on-the-fly session creation for revisit

When a transfer request arrives at `/transfer/xxx` via mTLS and no trust session exists:
1. The TLS handshake already proved the client is trusted (cert validated against CA bundle by the framework)
2. Create an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`, using the `X-Session-Id` header
3. Derive `payload_class` and `target_intent` from the endpoint:
   - `/transfer/text` → TEXT / CLIPBOARD_ONLY
   - `/transfer/image` → IMAGE / CLIPBOARD_OR_FILE
4. Process the transfer normally

No CN extraction or peer cert lookup is needed — the TLS layer already did the work.

### Decision 5: peerDeviceName for UI display

The mobile sends a human-readable device name at the **first encrypted opportunity** in each flow:

| Flow | First encrypted request | Mechanism |
|---|---|---|
| First visit (mobile→PC) | `/trust/apply` | `peer_device_name` body field (AES-GCM encrypted) |
| Revisit (mobile→PC) | `/transfer/xxx` | `X-Peer-Device-Name` HTTP header (mTLS-protected) |
| QR (PC→mobile) | `/trust/confirm` | `peer_device_name` body field (AES-GCM encrypted) |

Rationale:
- `/trust/handshake` is plaintext HTTP — sending the device name unencrypted is unnecessary
- `/trust/confirm` is late in the mobile→PC flow (step 3 of 3) — the PIN display phase is the most user-facing moment and benefits from showing the real device name, hence `/trust/apply` (step 2 of 3, first encrypted)
- The QR flow skips `/trust/apply` entirely (opt_code is already known from the QR), so `/trust/confirm` is the first encrypted request

**Mobile→PC data path:**
1. Mobile encrypts `{"action": "request_pin", "peer_device_name": "Alice's iPhone"}` with the session key
2. PC-side `_do_trust_apply()` decrypts the body and extracts `peer_device_name`
3. Stored on `TrustSession` as new `peer_device_name` attribute
4. Orchestrator's `_publish()` reads it from the trust session registry and includes `device_name` in every lifecycle event
5. `_on_lifecycle_event` handler extracts and passes `device_name` to `apply_session_event()`
6. `show_pin()` copies forward the previously-set `device_name`, so the PIN display phase automatically shows the real name

**QR flow data path:**
1. Mobile encrypts `{"action": "confirm", "opt_code": "...", "device_certificate_pem": "...", "peer_device_name": "Alice's iPhone"}` with the session key
2. PC-side `_do_trust_confirm()` (PC_TO_MOBILE branch) decrypts the body and extracts `peer_device_name`
3. Stored on `TrustSession` as new `peer_device_name` attribute (same attribute used by both flows)
4. `_do_transfer_download()` → `retrieve_stash_content()` marks the stash claimed and fires `on_stash_claimed(stash_id, peer_device_name)`
5. `QRTriggerMiniWindowFactory._mark_claimed()` passes the name to `QRTriggerMiniWindow.on_claimed()`
6. QR mini-window displays "Delivered to Alice's iPhone" instead of just "Delivered"

### Decision 6: No mDNS TXT format changes

The mDNS TXT records continue to include all existing fields (`signature`, `signature_key_id`, `timestamp_ms`, `device_id`, `device_name`, `tls_port`). The revisit flow simply does not use the identity-related fields (`signature`, `signature_key_id`, `timestamp_ms`, `device_id`) — it relies on the TLS cert CN instead. However, `device_name` and `tls_port` remain essential for connectivity and initial display.

## Risks / Trade-offs

- **[mTLS cert expiry]** X.509 certs have a 364-day validity. If a cert expires between shares, the TLS handshake will fail. → Mitigation: TLS failure triggers fallback to full trust handshake, which re-exchanges fresh certs.
- **[Session state visibility]** On-the-fly session creation means the mini-window may not show the full lifecycle (BOOTSTRAPPED→QUEUED→NEGOTIATING states are skipped). → Mitigation: The orchestrator publishes lifecycle events starting from TRANSFERRING state. The mini-window handles this as a valid entry point.
- **[Concurrent sessions]** If a transfer is in progress when another revisit transfer arrives, the single-session model rejects it. → Mitigation: Later sessions override existing ones for now. Future iterations will support multiple sessions.
- **[PC key rotation]** If the PC regenerates its identity (config directory lost), the mobile's stored cert becomes invalid. → Mitigation: TLS handshake fails → falls back to full trust handshake → re-exchanges certificates.

## Open Questions

- Should the mobile cache "stored cert exists" per PC to avoid the TLS handshake when no cert is stored? (Leaning: Yes — the mobile already checks its local cert store for the device_id, so no TLS attempt is made when no cert exists.)
- Should the PC persist `peer_device_name` alongside the stored cert for future sessions? (Leaning: Yes — store as keychain metadata or in a lightweight mapping, so the PC can display the device name even without the mobile explicitly sending it on revisit.)
