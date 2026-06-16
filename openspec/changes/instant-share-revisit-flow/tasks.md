## 1. PC: Revisit session creation in transfer endpoints

- [ ] 1.1 Create `_get_or_create_revisit_session()` helper in `https_tls_server.py` that creates an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING` when no trust session exists — the TLS handshake already proves the client is trusted (cert validated against CA bundle)
- [ ] 1.2 Add optional session creation to `_do_transfer_text()`, `_do_transfer_image()`, and `_do_transfer_download()` in `https_bootstrap.py` — when trust session is missing but the request came via mTLS, create revisit session; otherwise return 404/403 as before
- [ ] 1.3 No CN extraction needed — use `X-Session-Id` header as the session identifier for the on-the-fly session
- [ ] 1.4 Derive `payload_class` / `target_intent` from the endpoint for revisit sessions: `/transfer/text` → TEXT/CLIPBOARD_ONLY, `/transfer/image` → IMAGE/CLIPBOARD_OR_FILE

## 2. PC: peerDeviceName handling

- [ ] 2.1 Add `peer_device_name` attribute to `TrustSession` (default `""`), set in `_do_trust_apply()` from decrypted `/trust/apply` body (mobile→PC first visit)
- [ ] 2.2 Extract `peer_device_name` from the decrypted `/trust/confirm` body in the `PC_TO_MOBILE` branch and store on `TrustSession` (QR flow — `/trust/apply` is skipped)
- [ ] 2.3 Extract `X-Peer-Device-Name` header in `/transfer/xxx` handlers and include in the on-the-fly session's metadata (revisit)
- [ ] 2.4 Add `device_name` to the lifecycle event published by `InstantShareReceiverOrchestrator._publish()` (reads from trust session registry for first visit, from session metadata for revisit)
- [ ] 2.5 Update `InstantShareMiniWindowFactory._on_lifecycle_event()` to extract `device_name` from the event and pass it to the mini-window
- [ ] 2.6 Extend `QRTriggerHandler.on_stash_claimed` callback signature to `Callable[[str, str], None]` (stash_id, peer_device_name) and read `peer_device_name` from `TrustSession` in `retrieve_stash_content()`
- [ ] 2.7 Update `QRTriggerMiniWindowFactory` bridge signals and `_mark_claimed()` to receive and forward `peer_device_name`
- [ ] 2.8 Update `QRTriggerMiniWindow.on_claimed(peer_device_name: str = "")` to display "Delivered to {name}" instead of just "Delivered"

## 3. PC: Orchestrator support for revisit lifecycle

- [ ] 3.1 Add `handle_revisit_transfer()` method to `InstantShareReceiverOrchestrator` that publishes lifecycle events starting from `TRANSFERRING` state, skipping BOOTSTRAPPED→QUEUED→NEGOTIATING
- [ ] 3.2 Ensure mini-window correctly renders transfer progress for revisit sessions (already supports TRANSFERRING as a phase in `MiniWindowPhase`)

## 4. PC: Session registry for on-the-fly creation

- [ ] 4.1 Add `bootstrap_revisit(connection_config)` method to `InstantShareSessionRegistry` that creates a session directly (bypassing the active-session check if needed, or overriding existing as per current convention)
- [ ] 4.2 The revisit session starts at `TRANSFERRING` state (already allowed: BOOTSTRAPPED → TRANSFERRING is in `_ALLOWED_TRANSITIONS`)

## 5. Mobile (iOS): Revisit transfer flow

- [ ] 5.1 Implement blind mTLS transfer path: for any discovered PC, connect to `tls_port` with the mobile's X.509 client cert and POST payload to `/transfer/text` or `/transfer/image` without pre-checking stored certs — the TLS handshake itself determines trust
- [ ] 5.2 Set `X-Peer-Device-Name` header on transfer requests for revisit
- [ ] 5.3 Implement fallback logic: on TLS handshake failure or transfer error, fall back to the existing full trust handshake sequence (`/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`)
- [ ] 5.4 On successful fallback trust handshake, update stored X.509 certificate for the PC's `device_id` (handles key rotation)

## 6. Mobile (iOS): peerDeviceName in trust requests

- [ ] 6.1 Include `peer_device_name` field in the encrypted `/trust/apply` request body during first-share trust handshake (alongside `action: "request_pin"`)
- [ ] 6.2 Include `peer_device_name` field in the encrypted `/trust/confirm` request body during QR download flow (alongside `action: "confirm"`, `opt_code`, `device_certificate_pem`)

## 7. Telemetry

- [ ] 7.1 Add span for revisit transfer attempt (outcome: success, tls_handshake_failure, transfer_error, fallback_triggered)
- [ ] 7.2 Add span event for on-the-fly session creation on PC side

## 8. Testing and verification

- [ ] 8.1 Add unit test for `_get_or_create_revisit_session()` covering: trusted peer with stored cert, unknown peer (no stored cert), active session conflict
- [ ] 8.2 Add integration test: full revisit flow end-to-end (pre-trusted devices → mTLS transfer → delivery, no trust endpoints called)
- [ ] 8.3 Add integration test: revisit fallback flow (pre-trusted device but cert expired/rotated → TLS handshake fails → fallback trust handshake → transfer succeeds)
- [ ] 8.4 Add integration test: first-share flow unchanged (new device → full trust handshake → transfer)
- [ ] 8.5 Verify mini-window displays correct peer device name for first-share, revisit, and QR flows
- [ ] 8.6 Verify QR mini-window transitions from "Delivered" to "Delivered to {device_name}" when `peer_device_name` is present
