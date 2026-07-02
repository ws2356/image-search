## Why

Currently every mobile-to-PC instant share requires the full trust handshake (DH exchange → PIN verification → cert exchange), even when the mobile device has already established trust with the PC. Both sides already persist each other's X.509 certificates after first trust, but these are unused for skipping re-authentication. This adds unnecessary friction for repeat shares.

## What Changes

- **Mobile**: After mDNS discovery (provides connectivity only — hostname/IP + `tls_port`), blindly attempt direct mTLS transfer to `/transfer/xxx`. The TLS handshake itself determines the outcome: if both sides' certs are mutually trusted, the transfer proceeds; if the handshake fails, fall back to the full trust handshake. No pre-check of stored certs needed — just connect and let TLS decide.
- **Mobile**: Include `peerDeviceName` at the first encrypted opportunity in each flow: `peer_device_name` in the `/trust/apply` encrypted body (first visit), `X-Peer-Device-Name` header on `/transfer/xxx` (revisit), and `peer_device_name` in the `/trust/confirm` encrypted body (QR flow — the first AES-GCM-encrypted request since `/trust/apply` is skipped).
- **Mobile**: If the mTLS connection fails (TLS handshake failure — the SSL layer rejects untrusted client certs before any HTTP response), fall back to the existing full trust handshake flow. Revisit failure is NOT a fatal error.
- **PC**: Update `/transfer/text`, `/transfer/image`, and `/transfer/download` TLS endpoints to accept requests from previously-trusted peers that connect via mTLS without a prior trust session (on-the-fly session creation for revisit). The TLS handshake succeeding is sufficient proof of trust — no CN extraction or cert lookup needed, just create the session from the `X-Session-Id` header.

## Capabilities

### New Capabilities
- `revisit-transfer-skip-trust`: Mobile attempts direct mTLS transfer when a stored peer certificate exists. The mTLS handshake proves identity — no signature verification, no trust endpoints. If the TLS handshake fails (PC doesn't recognize the mobile's cert), fall back to the full trust handshake.
- `pc-revisit-session`: PC creates an on-the-fly `InstantShareSession` for previously-trusted peers connecting via mTLS without a prior trust session. The session starts at `TRANSFERRING` state with `TrustMode.TRUSTED_DIRECT`.

### Modified Capabilities
- `instant-share-secure-discovery-trust`: The discovery layer (mDNS) provides connectivity only. Device identity is derived from the TLS certificate CN during the mTLS handshake — no Ed25519 signature verification is required. The `signature` field in mDNS TXT records is not used for revisit recognition.

### Removed Capabilities
- `mdns-signature-verification`: No longer needed. The mTLS handshake inherently verifies both sides' identities via their X.509 certificates. An additional Ed25519 signature check over mDNS TXT records is redundant.

## Impact

- **PC**: `dt_image_search/instant_sharing/https_bootstrap.py` — transfer handler functions (`_do_transfer_text`, `_do_transfer_image`, `_do_transfer_download`) gain optional session checking (no trust session → attempt revisit session creation); `_do_trust_apply` and `_do_trust_confirm` extract `peer_device_name` and store on `TrustSession`. `dt_image_search/instant_sharing/trust_server.py` — `TrustSession` gains `peer_device_name` attribute. `dt_image_search/instant_sharing/session.py` — new `bootstrap_revisit()` method for on-the-fly session creation at TRANSFERRING state. `dt_image_search/instant_sharing/orchestrator.py` — new lifecycle path for revisit sessions; `_publish()` includes `device_name` from trust session. `dt_image_search/instant_sharing/qr_trigger_handler.py` — `on_stash_claimed` callback extended with `peer_device_name`. `dt_image_search/instant_sharing/qr_trigger_mini_window_factory.py` — bridge signals updated. `dt_image_search/instant_sharing/qr_trigger_mini_window.py` — `on_claimed()` displays device name. `dt_image_search/instant_sharing/mini_window_factory.py` — `_on_lifecycle_event()` extracts and passes `device_name`.
- **Mobile (iOS)**: Simplified revisit logic — stored cert check → mTLS transfer → success or fallback to trust handshake. `CertTools.swift` already extracts CN from TLS certs. Add `peerDeviceName` to `/trust/apply` body (first visit) and `/trust/confirm` body (QR flow) in `InstantShareTrustClient.swift` and `QRTriggerDownloadClient.swift` respectively.
- **No breaking changes**: The existing first-share trust flow remains intact as the fallback. mDNS TXT record format is unchanged (though `signature`/`signature_key_id`/`timestamp_ms` fields may become unused by revisit flow).
