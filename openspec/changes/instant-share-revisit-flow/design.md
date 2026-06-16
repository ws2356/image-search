## Context

The instant-share system already supports trust establishment between mobile (iOS) and PC via a three-step handshake (DH exchange → encrypted PIN → certificate exchange). After first trust, both sides persist each other's X.509 certificates, and the PC advertises an Ed25519 `signature` in its mDNS TXT records. However, currently every share repeats the full handshake—the persisted certificates and mDNS signatures are unused for skipping re-authentication.

This design implements the deferred "Signed mDNS advertisement verification and pinned direct HTTPS for future sharing" requirement from the original `instant-share-secure-discovery-trust` spec.

## Goals / Non-Goals

**Goals:**
- Mobile detects a previously-trusted PC from mDNS TXT records (device_id + Ed25519 signature)
- Mobile verifies the PC's identity using the Ed25519 public key acquired during first trust
- On successful verification, mobile skips the trust handshake and sends payloads directly via mTLS to `/transfer/xxx`
- PC-side transfer endpoints accept requests from previously-trusted mTLS peers without a prior session
- If revisit fails at any point, mobile falls back gracefully to the existing full trust handshake flow

**Non-Goals:**
- Changing the mDNS TXT record format (already includes `signature`, `signature_key_id`, `timestamp_ms`)
- Replacing the existing trust handshake flow (it remains as the fallback)
- PC-to-mobile revisit (QR flow) — this change is mobile-to-PC only
- BLE-based revisit (the BLE `TrustMode.TRUSTED_DIRECT` path is separate)
- Certificate revocation or expiry notification mechanisms

## Decisions

### Decision 1: Ed25519 public key exchange during first trust

During `/trust/confirm`, the PC's encrypted response already includes `device_certificate_pem` (the PC's X.509 cert). We add a new field `ed25519_public_key_pem` containing the PC's Ed25519 public key in SubjectPublicKeyInfo PEM format (exported via `PersistentEd25519SessionSigner.public_key_pem()`).

The mobile stores both the X.509 cert and the Ed25519 public key, keyed by `device_id`. This gives the mobile everything needed for future mDNS signature verification: the device identity (from device_id), the Ed25519 public key (to verify signatures), and the X.509 cert (for mTLS).

**Alternative considered**: Embed the Ed25519 key in an X.509 extension. Rejected because it complicates cert parsing on iOS and adds non-standard cert fields. Storing it as a separate field is simpler and more portable.

### Decision 2: mDNS signature verification on mobile

The mobile extracts `device_id`, `signature`, `signature_key_id`, and `timestamp_ms` from the mDNS TXT record. It looks up the stored Ed25519 public key by `device_id` (which is also the `signature_key_id` value).

The signed message format is already defined by `PersistentEd25519SessionSigner.device_signature_advertisement()`: `f"{device_id}:{timestamp_ms}"`. The mobile reconstructs this message and verifies the base64url-decoded Ed25519 signature.

Timestamp freshness check: the mobile compares `timestamp_ms` against its own clock, rejecting signatures older than 300 seconds (5 minutes). This window is generous enough to account for clock skew while preventing replay of stale advertisements (mDNS TXT is refreshed every 5 seconds with a 120s TTL).

### Decision 3: Revisit transfer flow on mobile (no session pre-establishment)

When signature verification succeeds, the mobile:
1. Connects to `tls_port` (from mDNS TXT) via HTTPS with its own X.509 certificate for mTLS
2. Generates a new `X-Session-Id` (UUID v4)
3. POSTs payload to `/transfer/text` or `/transfer/image` with standard headers including `X-Device-Id` set to the mobile's device_id

No `/trust/handshake`, `/trust/apply`, or `/trust/confirm` calls are made. The mTLS handshake itself proves the mobile's identity (its cert was already stored on the PC during first trust).

The mobile also handles `/transfer/download` for potential future PC-to-mobile revisit, though this change focuses on mobile-to-PC.

### Decision 4: PC on-the-fly session creation for revisit

Currently, the `/transfer/xxx` TLS endpoints require a session to exist and be in a trusted state. For revisit, there is no session yet.

The PC transfer handlers are updated to detect the "no session" case:
1. Request arrives via mTLS (TLS client cert already verified by the SSL layer)
2. Extract client certificate CN (which is the mobile's `device_id`)
3. Look up the peer cert in the keychain to confirm it's a known trusted device
4. If trusted, create an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT`, state `TRANSFERRING`, and the payload metadata from request headers
5. Process the transfer normally

**Alternative considered**: Require a lightweight "revisit bootstrap" endpoint before transfer. Rejected because it adds an extra round-trip and the mTLS handshake already establishes identity. The existing trust material (keychain cert) is sufficient authorization.

### Decision 5: Fallback strategy

The mobile implements a sequential fallback:
1. Try mDNS signature verification → if fail, go to step 4
2. Try mTLS direct transfer to `/transfer/xxx` → if fail (connection error, TLS error, HTTP 4xx/5xx), go to step 4
3. Transfer succeeds → done
4. Fall back to full trust handshake: `/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`

The fallback path re-runs the full trust establishment, which also re-exchanges certificates and Ed25519 keys (handles key rotation). The mobile should clear and re-store the peer's certs/keys on successful fallback trust to handle key changes.

If the mTLS connection fails specifically with a certificate verification error (e.g., the PC's cert expired and was regenerated), the fallback trust handshake will exchange the new cert. If the fallback trust handshake itself fails, the user sees an error.

### Decision 6: No changes to mDNS TXT format

The existing mDNS TXT records already include all required fields: `device_id`, `signature`, `signature_key_id`, `timestamp_ms`. No format changes are needed. The `tls_port` field is already advertised for the mobile to know where to connect for mTLS transfer.

## Risks / Trade-offs

- **[Clock skew]** Mobile and PC clocks may differ, causing legitimate signatures to appear expired or future-dated. → Mitigation: 300-second timestamp tolerance window. The mobile uses its own clock as reference, not trusting the PC's timestamp.
- **[Ed25519 key rotation]** If the PC regenerates its Ed25519 signing key (e.g., config directory lost), the mobile's stored key becomes invalid. → Mitigation: Signature verification fails → falls back to full trust handshake → re-exchanges both X.509 cert and Ed25519 key. No user-visible breakage, just one extra round-trip.
- **[mTLS cert expiry]** X.509 certs have a 364-day validity. If a cert expires between shares, mTLS will fail. → Mitigation: mTLS failure triggers fallback to full trust handshake, which re-exchanges fresh certs.
- **[Session state visibility]** On-the-fly session creation means the mini-window may not show the full lifecycle (BOOTSTRAPPED→QUEUED→NEGOTIATING states are skipped). → Mitigation: The orchestrator should handle `TRANSFERRING` as a valid initial state for revisit sessions. The mini-window shows transfer progress as usual.
- **[Concurrent revisit + first-share]** If a first-share trust handshake is in progress for device A when device B attempts a revisit transfer, the single-session model may reject B. → Mitigation: This is consistent with existing behavior (single active session). The revisit transfer will receive 409/RECEIVER_BUSY and the mobile will retry or fall back.

## Open Questions

- Should the mobile cache "revisit capable" status per device to avoid re-verifying the signature on every share within a session? (Leaning: No — signature verification is cheap and mDNS TXT refreshes every 5s, so per-share verification is fine.)
- Should the PC's Ed25519 key be included in the SAN or an extension of the X.509 cert to reduce the number of stored items? (Leaning: No — Decision 1 already resolves this with a simple extra field.)
