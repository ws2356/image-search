## Why

Currently every mobile-to-PC instant share requires the full trust handshake (DH exchange → PIN verification → cert exchange), even when the mobile device has already established trust with the PC. Both sides already persist each other's X.509 certificates after first trust, but these are unused for skipping re-authentication. This adds unnecessary friction for repeat shares.

## What Changes

- **Mobile**: After mDNS discovery (provides connectivity only — hostname/IP + `tls_port`), extract the PC's `device_id` from its TLS certificate CN during the mTLS handshake (already implemented in `CertTools.swift`). If a stored peer certificate exists for this `device_id`, attempt direct mTLS transfer to `/transfer/xxx`. The mTLS handshake itself proves identity — no separate signature verification needed.
- **Mobile**: Include `peerDeviceName` in the transfer request header `X-Peer-Device-Name` so the PC can display which device is sharing (for revisit). Include `peer_device_name` in the `/trust/confirm` encrypted body (for first visit).
- **Mobile**: If the mTLS connection fails (TLS handshake failure — the SSL layer rejects untrusted client certs before any HTTP response), fall back to the existing full trust handshake flow. Revisit failure is NOT a fatal error.
- **PC**: Update `/transfer/text`, `/transfer/image`, and `/transfer/download` TLS endpoints to accept requests from previously-trusted peers that connect via mTLS without a prior trust session (on-the-fly session creation for revisit). The session check is made optional — when no trust session exists, extract the client certificate CN and look up the stored peer cert to authorize the transfer.
- **PC**: Extract the client certificate CN from the mTLS connection in the transfer handlers (minimal TLS change — existing cert validation and public key comparison remain intact).

## Capabilities

### New Capabilities
- `revisit-transfer-skip-trust`: Mobile attempts direct mTLS transfer when a stored peer certificate exists. The mTLS handshake proves identity — no signature verification, no trust endpoints. If the TLS handshake fails (PC doesn't recognize the mobile's cert), fall back to the full trust handshake.
- `pc-revisit-session`: PC creates an on-the-fly `InstantShareSession` for previously-trusted peers connecting via mTLS without a prior trust session. The session starts at `TRANSFERRING` state with `TrustMode.TRUSTED_DIRECT`.

### Modified Capabilities
- `instant-share-secure-discovery-trust`: The discovery layer (mDNS) provides connectivity only. Device identity is derived from the TLS certificate CN during the mTLS handshake — no Ed25519 signature verification is required. The `signature` field in mDNS TXT records is not used for revisit recognition.

### Removed Capabilities
- `mdns-signature-verification`: No longer needed. The mTLS handshake inherently verifies both sides' identities via their X.509 certificates. An additional Ed25519 signature check over mDNS TXT records is redundant.

## Impact

- **PC**: `dt_image_search/instant_sharing/https_tls_server.py` — transfer handlers extract client cert CN and create on-the-fly revisit sessions. `dt_image_search/instant_sharing/https_bootstrap.py` — transfer handler functions (`_do_transfer_text`, `_do_transfer_image`, `_do_transfer_download`) gain optional session checking (no trust session → attempt revisit session creation). `dt_image_search/instant_sharing/session.py` — new `bootstrap_revisit()` method for on-the-fly session creation at TRANSFERRING state. `dt_image_search/instant_sharing/orchestrator.py` — new lifecycle path for revisit sessions.
- **Mobile (iOS)**: Simplified revisit logic — stored cert check → mTLS transfer → success or fallback to trust handshake. `CertTools.swift` already extracts CN from TLS certs. Add `peerDeviceName` handling.
- **No breaking changes**: The existing first-share trust flow remains intact as the fallback. mDNS TXT record format is unchanged (though `signature`/`signature_key_id`/`timestamp_ms` fields may become unused by revisit flow).
