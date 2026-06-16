## 1. PC: Ed25519 public key exchange in trust confirm

- [ ] 1.1 Add `ed25519_public_key_pem` field to the encrypted `/trust/confirm` response in `https_bootstrap.py`, sourced from `SenderIdentity.public_key_pem()` (requires passing sender_identity through to the trust confirm handler)
- [ ] 1.2 Update `InstantShareHTTPServer` and `InstantShareTLSServer` constructors to accept an optional `sender_identity` parameter and thread it through `_Deps`

## 2. PC: Revisit session creation in transfer endpoints

- [ ] 2.1 Create `_get_or_create_revisit_session()` helper in `https_tls_server.py` that extracts the client cert CN from the request, looks up the peer cert in the keychain, and creates an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`
- [ ] 2.2 Update `_do_transfer_text()` in `https_bootstrap.py` to detect missing session, call `_get_or_create_revisit_session()`, and set `payload_class=TEXT` / `target_intent=CLIPBOARD_ONLY` for revisit sessions
- [ ] 2.3 Update `_do_transfer_image()` in `https_bootstrap.py` to detect missing session, call `_get_or_create_revisit_session()`, and set `payload_class=IMAGE` / `target_intent=CLIPBOARD_OR_FILE` for revisit sessions
- [ ] 2.4 Update `_do_transfer_download()` in `https_bootstrap.py` to support revisit sessions (on-the-fly creation from trusted mTLS peer)
- [ ] 2.5 Wire `sender_identity` from `InstantShareRuntime` to the TLS and HTTP server constructors so Ed25519 key is available during `/trust/confirm`

## 3. PC: Orchestrator support for revisit lifecycle

- [ ] 3.1 Update `InstantShareReceiverOrchestrator` to accept sessions initialized at `TRANSFERRING` state (skip BOOTSTRAPPED→QUEUED→NEGOTIATING transitions for `TRUSTED_DIRECT` sessions)
- [ ] 3.2 Ensure mini-window correctly renders transfer progress for revisit sessions (should be identical to first-share sessions)

## 4. Mobile (iOS): Ed25519 key storage and retrieval

- [ ] 4.1 Add Ed25519 public key persistence to the iOS trust client: during `/trust/confirm` response handling, store `ed25519_public_key_pem` in iOS Keychain keyed by the PC's `device_id`
- [ ] 4.2 Add lookup function to retrieve stored Ed25519 public key by `device_id` from iOS Keychain

## 5. Mobile (iOS): mDNS signature verification

- [ ] 5.1 Implement Ed25519 signature verification in the iOS mDNS discovery/browser code: reconstruct message `"{device_id}:{timestamp_ms}"`, base64url-decode the signature, verify against stored Ed25519 public key
- [ ] 5.2 Implement timestamp freshness check: reject signatures where `|mobile_time_ms - timestamp_ms| > 300_000`
- [ ] 5.3 Integrate verification into the device selection flow: after resolving mDNS TXT records, classify each discovered PC as "revisit-eligible" (verified) or "first-share" (unverified)

## 6. Mobile (iOS): Revisit transfer flow

- [ ] 6.1 Implement direct mTLS transfer path: when a revisit-eligible PC is selected, connect to `tls_port` with the mobile's X.509 client cert and POST payload to `/transfer/text` or `/transfer/image` without calling trust endpoints
- [ ] 6.2 Implement fallback logic: on mTLS connection failure or transfer error, fall back to the existing full trust handshake sequence (`/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`)
- [ ] 6.3 On successful fallback trust handshake, update stored X.509 cert and Ed25519 public key for the PC's `device_id` (handles key rotation)

## 7. Telemetry

- [ ] 7.1 Add span for mDNS signature verification (outcome: verified, no_key, wrong_key, stale_timestamp)
- [ ] 7.2 Add span for revisit transfer attempt (outcome: success, mTLS_failure, transfer_error, fallback_triggered)
- [ ] 7.3 Add span event for on-the-fly session creation on PC side

## 8. Testing and verification

- [ ] 8.1 Add unit test for `_get_or_create_revisit_session()` covering: trusted peer with stored cert, unknown peer, active session conflict
- [ ] 8.2 Add unit test for Ed25519 signature verification: valid signature, wrong key, stale timestamp, missing key
- [ ] 8.3 Add integration test: full revisit flow end-to-end (pre-trusted devices → mDNS signature verify → mTLS transfer → delivery)
- [ ] 8.4 Add integration test: revisit fallback flow (pre-trusted device but cert expired → mTLS fails → fallback trust handshake → transfer succeeds)
- [ ] 8.5 Add integration test: first-share flow unchanged (new device → full trust handshake → transfer)
