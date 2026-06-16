## 1. PC: Revisit session creation in transfer endpoints

- [ ] 1.1 Create `_get_or_create_revisit_session()` helper in `https_tls_server.py` that extracts the client cert CN from the request scope, looks up the peer cert in the keychain via `load_peer_certificate()`, and creates an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING`
- [ ] 1.2 Add `client_cert_cn` optional parameter to `_do_transfer_text()`, `_do_transfer_image()`, and `_do_transfer_download()` in `https_bootstrap.py` — when trust session is missing but `client_cert_cn` is provided and a peer cert exists, create revisit session; otherwise return 404/403 as before
- [ ] 1.3 Update TLS transfer handlers in `https_tls_server.py` (`_build_tls_app`) to extract the client cert CN from `request.scope` (via transport) and pass it to the handler functions
- [ ] 1.4 Derive `payload_class` / `target_intent` from the endpoint for revisit sessions: `/transfer/text` → TEXT/CLIPBOARD_ONLY, `/transfer/image` → IMAGE/CLIPBOARD_OR_FILE

## 2. PC: peerDeviceName handling

- [ ] 2.1 Extract `peer_device_name` from the decrypted `/trust/confirm` request body and store in the trust session or instant-share session metadata
- [ ] 2.2 Extract `X-Peer-Device-Name` header in `/transfer/xxx` handlers and include in the on-the-fly session's metadata
- [ ] 2.3 Add `device_name` to the lifecycle event published by `InstantShareReceiverOrchestrator._publish()`
- [ ] 2.4 Update `InstantShareMiniWindowFactory._on_lifecycle_event()` to extract `device_name` from the event and pass it to the mini-window

## 3. PC: Orchestrator support for revisit lifecycle

- [ ] 3.1 Add `handle_revisit_transfer()` method to `InstantShareReceiverOrchestrator` that publishes lifecycle events starting from `TRANSFERRING` state, skipping BOOTSTRAPPED→QUEUED→NEGOTIATING
- [ ] 3.2 Ensure mini-window correctly renders transfer progress for revisit sessions (already supports TRANSFERRING as a phase in `MiniWindowPhase`)

## 4. PC: Session registry for on-the-fly creation

- [ ] 4.1 Add `bootstrap_revisit(connection_config)` method to `InstantShareSessionRegistry` that creates a session directly (bypassing the active-session check if needed, or overriding existing as per current convention)
- [ ] 4.2 The revisit session starts at `TRANSFERRING` state (already allowed: BOOTSTRAPPED → TRANSFERRING is in `_ALLOWED_TRANSITIONS`)

## 5. Mobile (iOS): Revisit transfer flow

- [ ] 5.1 Implement direct mTLS transfer path: when a discovered PC is selected and a stored peer cert exists, connect to `tls_port` with the mobile's X.509 client cert and POST payload to `/transfer/text` or `/transfer/image` without calling trust endpoints
- [ ] 5.2 Set `X-Peer-Device-Name` header on transfer requests for revisit
- [ ] 5.3 Implement fallback logic: on TLS handshake failure or transfer error, fall back to the existing full trust handshake sequence (`/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`)
- [ ] 5.4 On successful fallback trust handshake, update stored X.509 certificate for the PC's `device_id` (handles key rotation)

## 6. Mobile (iOS): peerDeviceName in trust confirm

- [ ] 6.1 Include `peer_device_name` field in the encrypted `/trust/confirm` request body during first-share trust handshake

## 7. Telemetry

- [ ] 7.1 Add span for revisit transfer attempt (outcome: success, tls_handshake_failure, transfer_error, fallback_triggered)
- [ ] 7.2 Add span event for on-the-fly session creation on PC side

## 8. Testing and verification

- [ ] 8.1 Add unit test for `_get_or_create_revisit_session()` covering: trusted peer with stored cert, unknown peer (no stored cert), active session conflict
- [ ] 8.2 Add integration test: full revisit flow end-to-end (pre-trusted devices → mTLS transfer → delivery, no trust endpoints called)
- [ ] 8.3 Add integration test: revisit fallback flow (pre-trusted device but cert expired/rotated → TLS handshake fails → fallback trust handshake → transfer succeeds)
- [ ] 8.4 Add integration test: first-share flow unchanged (new device → full trust handshake → transfer)
- [ ] 8.5 Verify mini-window displays correct peer device name for both first-share and revisit flows
