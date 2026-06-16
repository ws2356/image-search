## Context

The instant-share system already supports trust establishment between mobile (iOS) and PC via a three-step handshake (DH exchange → encrypted PIN → certificate exchange). After first trust, both sides persist each other's X.509 certificates. However, currently every share repeats the full handshake — the persisted certificates are unused for skipping re-authentication.

The key insight: **mTLS already proves identity.** The TLS handshake verifies both the server's certificate (mobile authenticates the PC) and the client's certificate (PC authenticates the mobile). If both sides have each other's certs from a previous trust exchange, the mTLS handshake alone is sufficient proof — no additional Ed25519 signature verification over mDNS TXT records is needed.

The PC side already loads trusted peer certs into the mTLS CA bundle (`load_all_peer_certificates()` at server start + dynamic injection via `add_peer_certificate()` after trust confirm). When an untrusted client connects, the TLS handshake fails at the SSL layer (before any HTTP exchange) — there is no 403 response, the connection is simply refused.

## Goals / Non-Goals

**Goals:**
- Mobile identifies a previously-trusted PC from its TLS certificate CN (already extracted via `CertTools.swift`)
- If mobile has a stored peer cert for that `device_id`, it attempts direct mTLS transfer to `/transfer/xxx`
- PC-side TLS transfer endpoints accept requests from trusted mTLS peers without a prior trust session (on-the-fly session creation)
- If the TLS handshake fails (PC doesn't trust the mobile's cert), mobile falls back to the full trust handshake
- Mobile sends `peerDeviceName` so the PC can display which device is sharing

**Non-Goals:**
- Changing the mDNS TXT record format
- Replacing the existing first-share trust handshake flow (it remains as the fallback)
- PC-to-mobile revisit (QR flow) — this change is mobile-to-PC only
- BLE-based revisit (BLE provides connectivity discovery only, same as mDNS)
- Certificate revocation or expiry notification mechanisms
- Supporting multiple concurrent sessions (later sessions override existing ones for now)

## Decisions

### Decision 1: Identity from TLS certificate CN, not mDNS TXT

mDNS provides connectivity only (hostname/IP + `tls_port`). Device identity is derived from the PC's TLS certificate CN during the mTLS handshake. The mobile already extracts the CN via `CertTools.swift`. This eliminates the need for `device_id` in mDNS TXT records and for Ed25519 signature verification.

The PC's certificate CN *is* the `device_id` — set during cert generation in `device_identity.py` line 334:
```python
subject = issuer = x509.Name([
    x509.NameAttribute(NameOID.COMMON_NAME, device_id),
])
```

Both sides' certs use the same convention, so the TLS handshake carries all identity information needed.

### Decision 2: Revisit = direct mTLS transfer attempt

When the mobile discovers a PC and has a stored peer cert for the CN extracted from the TLS handshake, it:
1. Connects to `tls_port` (from mDNS) via HTTPS with its own X.509 client certificate
2. Generates a new `X-Session-Id` (UUID v4)
3. Sets `X-Peer-Device-Name` header to a human-readable device name
4. POSTs payload to `/transfer/text` or `/transfer/image` directly

No `/trust/handshake`, `/trust/apply`, or `/trust/confirm` calls are made. The mTLS handshake itself authenticates both sides.

### Decision 3: Fallback triggered by TLS handshake failure

When the mobile's client cert is not in the PC's CA bundle, the TLS handshake fails at the SSL layer — the connection is refused, and the PC never receives an HTTP request. The mobile detects this as a connection/TLS error and falls back to the full trust handshake.

There are two failure modes:
1. **TLS handshake failure** (cert not trusted) → connection refused → mobile falls back to trust handshake
2. **Application-layer conflict** (e.g., another session active) → PC returns 409/RECEIVER_BUSY → mobile retries or falls back

### Decision 4: PC on-the-fly session creation for revisit

When a transfer request arrives at `/transfer/xxx` via mTLS and no trust session exists:
1. Extract client certificate CN (mobile's `device_id`) from the TLS connection
2. Look up the peer cert in the keychain to confirm it's a known trusted device
3. If trusted, create an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`
4. Derive `payload_class` and `target_intent` from the endpoint:
   - `/transfer/text` → TEXT / CLIPBOARD_ONLY
   - `/transfer/image` → IMAGE / CLIPBOARD_OR_FILE
5. Process the transfer normally

The TLS layer already validated the client cert against the CA bundle (containing all trusted peer certs) and verified the public key. The app layer only needs to extract the CN for session identification.

### Decision 5: Minimal TLS handshake changes

The existing TLS configuration (`ssl_cert_reqs=ssl.CERT_REQUIRED`, CA bundle from keychain) remains intact. The only addition is extracting the client certificate CN from the request scope in the transfer handlers. The cert validation (signature, public key, expiry) is handled entirely by the SSL layer.

### Decision 6: peerDeviceName for UI display

The mobile sends a human-readable device name in two places:
- **First visit**: `peer_device_name` field in the encrypted `/trust/confirm` request body
- **Revisit**: `X-Peer-Device-Name` HTTP header in `/transfer/xxx` requests

The PC stores this name in the session and includes it in the lifecycle event published to the event bus. The mini-window already supports `MiniWindowState.device_name` — this just needs to be populated from the lifecycle event.

### Decision 7: No mDNS TXT format changes

The mDNS TXT records continue to include all existing fields (`signature`, `signature_key_id`, `timestamp_ms`, `device_id`, `device_name`, `tls_port`). The revisit flow simply does not use the identity-related fields (`signature`, `signature_key_id`, `timestamp_ms`, `device_id`) — it relies on the TLS cert CN instead. However, `device_name` and `tls_port` remain essential for connectivity and initial display.

## Risks / Trade-offs

- **[mTLS cert expiry]** X.509 certs have a 364-day validity. If a cert expires between shares, the TLS handshake will fail. → Mitigation: TLS failure triggers fallback to full trust handshake, which re-exchanges fresh certs.
- **[Session state visibility]** On-the-fly session creation means the mini-window may not show the full lifecycle (BOOTSTRAPPED→QUEUED→NEGOTIATING states are skipped). → Mitigation: The orchestrator publishes lifecycle events starting from TRANSFERRING state. The mini-window handles this as a valid entry point.
- **[Concurrent sessions]** If a transfer is in progress when another revisit transfer arrives, the single-session model rejects it. → Mitigation: Later sessions override existing ones for now. Future iterations will support multiple sessions.
- **[PC key rotation]** If the PC regenerates its identity (config directory lost), the mobile's stored cert becomes invalid. → Mitigation: TLS handshake fails → falls back to full trust handshake → re-exchanges certificates.

## Open Questions

- Should the mobile cache "stored cert exists" per PC to avoid the TLS handshake when no cert is stored? (Leaning: Yes — the mobile already checks its local cert store for the device_id, so no TLS attempt is made when no cert exists.)
- Should the PC persist `peer_device_name` alongside the stored cert for future sessions? (Leaning: Yes — store as keychain metadata or in a lightweight mapping, so the PC can display the device name even without the mobile explicitly sending it on revisit.)
