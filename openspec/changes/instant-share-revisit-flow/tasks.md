## 1. PC: Revisit session creation in transfer endpoints

- [x] 1.1 Create `_try_create_revisit_session()` helper in `https_bootstrap.py` that creates an on-the-fly `InstantShareSession` with `TrustMode.TRUSTED_DIRECT` and state `TRANSFERRING` when no trust session exists — the TLS handshake already proves the client is trusted (cert validated against CA bundle)
- [x] 1.2 Add optional session creation to `_do_transfer_text()` and `_do_transfer_image()` in `https_bootstrap.py` — when trust session is missing but the request came via mTLS, create revisit session; otherwise return 404/403 as before. `_do_transfer_download()` is unchanged (QR flow requires trust session)
- [x] 1.3 No CN extraction needed — use `X-Session-Id` header as the session identifier for the on-the-fly session
- [x] 1.4 Derive `payload_class` / `target_intent` from the endpoint for revisit sessions: `/transfer/text` → TEXT/CLIPBOARD_ONLY, `/transfer/image` → IMAGE/CLIPBOARD_OR_FILE

## 2. PC: peerDeviceName handling

- [x] 2.1 Add `peer_device_name` attribute to `TrustSession` (default `""`), set in `_do_trust_apply()` from decrypted `/trust/apply` body (mobile→PC first visit)
- [x] 2.2 Extract `peer_device_name` from the decrypted `/trust/confirm` body in the `PC_TO_MOBILE` branch and store on `TrustSession` (QR flow — `/trust/apply` is skipped)
- [x] 2.3 Extract `X-Peer-Device-Name` header in `/transfer/xxx` handlers and include in the on-the-fly session's metadata (revisit)
- [x] 2.4 Add `device_name` to the lifecycle event published by `InstantShareReceiverOrchestrator._publish()` (reads from trust session registry for first visit, from session metadata for revisit)
- [x] 2.5 Update `InstantShareMiniWindowFactory._on_lifecycle_event()` to extract `device_name` from the event and pass it to the mini-window
- [x] 2.6 Extend `QRTriggerHandler.on_stash_claimed` callback signature to `Callable[[str, str], None]` (stash_id, peer_device_name) and read `peer_device_name` from `TrustSession` in `retrieve_stash_content()`
- [x] 2.7 Update `QRTriggerMiniWindowFactory` bridge signals and `_mark_claimed()` to receive and forward `peer_device_name`
- [x] 2.8 Update `QRTriggerMiniWindow.on_claimed(peer_device_name: str = "")` to display "Delivered to {name}" instead of just "Delivered"

## 3. PC: Orchestrator support for revisit lifecycle

- [x] 3.1 Add `handle_revisit_transfer()` method to `InstantShareReceiverOrchestrator` that publishes lifecycle events starting from `TRANSFERRING` state, skipping BOOTSTRAPPED→QUEUED→NEGOTIATING
- [x] 3.2 Ensure mini-window correctly renders transfer progress for revisit sessions (already supports TRANSFERRING as a phase in `MiniWindowPhase`)

## 4. PC: Session registry for on-the-fly creation

- [x] 4.1 Add `bootstrap_revisit(connection_config)` method to `InstantShareSessionRegistry` that creates a session directly (bypassing the active-session check if needed, or overriding existing as per current convention)
- [x] 4.2 The revisit session starts at `TRANSFERRING` state (already allowed: BOOTSTRAPPED → TRANSFERRING is in `_ALLOWED_TRANSITIONS`)

## 5. Mobile (iOS): Revisit transfer flow

- [x] 5.1 Implement blind mTLS transfer path: for any discovered PC, connect to `tls_port` with the mobile's X.509 client cert and POST payload to `/transfer/text` or `/transfer/image` without pre-checking stored certs — the TLS handshake itself determines trust
- [x] 5.2 Set `X-Peer-Device-Name` header on transfer requests for revisit
- [x] 5.3 Implement fallback logic: on TLS handshake failure or transfer error, fall back to the existing full trust handshake sequence (`/trust/handshake` → `/trust/apply` → `/trust/confirm` → `/transfer/xxx`)
- [x] 5.4 On successful fallback trust handshake, update stored X.509 certificate for the PC's `device_id` (handles key rotation)

## 6. Mobile (iOS): peerDeviceName in trust requests

- [x] 6.1 Include `peer_device_name` field in the encrypted `/trust/apply` request body during first-share trust handshake (alongside `action: "request_pin"`)
- [x] 6.2 Include `peer_device_name` field in the encrypted `/trust/confirm` request body during QR download flow (alongside `action: "confirm"`, `opt_code`, `device_certificate_pem`)

## 7. Telemetry

- [x] 7.1 Add span for revisit transfer attempt (outcome: success, tls_handshake_failure, transfer_error, fallback_triggered) — `handle_revisit_transfer` already wraps in `add_span("instant_share.revisit.transfer")`
- [x] 7.2 Add span event for on-the-fly session creation on PC side — covered by the same `instant_share.revisit.transfer` span in `handle_revisit_transfer`

## 8. Testing and verification

- [x] 8.1 Add unit test for `bootstrap_revisit()` covering: session creation with TRUSTED_DIRECT mode and TRANSFERRING state
- [ ] 8.2 Manual test: full revisit flow end-to-end (pre-trusted devices → mTLS transfer → delivery, no trust endpoints called)
- [ ] 8.3 Manual test: revisit fallback flow (pre-trusted device but cert expired/rotated → TLS handshake fails → fallback trust handshake → transfer succeeds)
- [ ] 8.4 Manual test: first-share flow unchanged (new device → full trust handshake → transfer)
- [ ] 8.5 Manual test: mini-window displays correct peer device name for first-share, revisit, and QR flows
- [ ] 8.6 Manual test: QR mini-window transitions from "Delivered" to "Delivered to {device_name}" when `peer_device_name` is present
