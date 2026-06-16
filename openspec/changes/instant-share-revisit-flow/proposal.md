## Why

Currently every mobile-to-PC instant share requires the full trust handshake (DH exchange → PIN verification → cert exchange), even when the mobile device has already established trust with the PC. The PC already advertises an Ed25519 `signature` in its mDNS TXT records and stores peer X.509 certificates after first trust, but these are unused for skipping re-authentication. This adds unnecessary friction for repeat shares.

## What Changes

- **Mobile**: After mDNS discovery, extract `device_id` and `signature` from TXT records. Look up the previously-trusted peer certificate by `device_id`. Verify the Ed25519 `signature` using the peer's known public key (derived from the stored X.509 cert). If verification succeeds, skip the trust handshake/PIN/cert-exchange flow and proceed directly to mTLS transfer.
- **Mobile**: If mTLS connection to `/transfer/xxx` fails (e.g., cert expired, not recognized), fall back to the existing full trust handshake flow.
- **PC**: Update `/transfer/text`, `/transfer/image`, and `/transfer/download` endpoints to accept requests from previously-trusted peers that connect via mTLS without a prior session (on-the-fly session creation for revisit).
- **PC**: mDNS TXT `signature` field must be verifiable against the same Ed25519 key material that was shared during the initial trust handshake. The public key must be derivable from or associated with the stored peer X.509 certificate.

## Capabilities

### New Capabilities
- `mdns-signature-verification`: Mobile client verifies Ed25519 signature from mDNS TXT records against a previously-trusted peer's public key, confirming identity before skipping trust handshake.
- `revisit-transfer-skip-trust`: When mDNS signature verification succeeds, mobile skips the full DH/PIN/cert-exchange flow and sends payloads directly via mTLS to `/transfer/xxx` endpoints.
- `pc-revisit-session`: PC creates an on-the-fly session for previously-trusted peers connecting via mTLS without a prior trust handshake, enabling revisit transfers without a pre-established session.

### Modified Capabilities
- `instant-share-secure-discovery-trust`: The deferred "Signed mDNS advertisement verification and pinned direct HTTPS for future sharing" requirement is now being implemented. The `signature` field in mDNS TXT records becomes the primary mechanism for revisit detection.

## Impact

- **PC**: `dt_image_search/instant_sharing/https_tls_server.py` — transfer endpoints gain revisit session creation. `dt_image_search/identity/device_identity.py` — may need Ed25519 public key association with stored peer certs. `dt_image_search/instant_sharing/sender_validation.py` — Ed25519 key material needs to be extractable/persistable for mobile verification.
- **Mobile (iOS)**: New mDNS TXT signature verification logic in the Share Extension (or AuBackup app). Peer certificate/Ed25519 key storage updates. Fallback path to existing trust handshake on mTLS failure.
- **No breaking changes**: The existing first-share trust flow remains intact as the fallback.
