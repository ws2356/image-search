## 1. Session Registry Refactor

- [ ] 1.1 Refactor `InstantShareSessionRegistry._active_session` from `Optional[InstantShareSession]` to `dict[str, InstantShareSession]` keyed by `session_id`
- [ ] 1.2 Update `bootstrap()` to create new sessions without checking for active sessions; remove `RECEIVER_BUSY_SINGLE_SESSION` raise
- [ ] 1.3 Add `RECEIVER_BUSY_MAX_SESSIONS` error code to `ErrorCode` enum; enforce configurable capacity limit (default 8) in `bootstrap()`
- [ ] 1.4 Update `transition()`, `get_session()`, and all other methods to accept and route by `session_id`
- [ ] 1.5 Add `get_active_sessions()` method returning all non-terminal-state sessions
- [ ] 1.6 Remove `bootstrap_revisit()` override logic — revisit sessions now create independent entries via `bootstrap()`
- [ ] 1.7 Add terminal session TTL cleanup: oneshot timer per session entering terminal state, remove from registry after 60s
- [ ] 1.8 Add `last_updated` timestamp to `InstantShareSession` and update it on every `transition()`

## 2. Trust Session Registry Refactor

- [ ] 2.1 Refactor `TrustSessionRegistry._session` from `Optional[TrustSession]` to `dict[str, TrustSession]` keyed by `session_id`
- [ ] 2.2 Update `create_handshake_session()` to accept and store by `session_id`; remove single-session constraint
- [ ] 2.3 Update `get_session()`, `complete_handshake()`, and all accessors to route by `session_id`
- [ ] 2.4 Ensure DH key material isolation between concurrent trust sessions (each session has independent keypair and nonces)
- [ ] 2.5 Add terminal trust session TTL cleanup matching the same 60s pattern

## 3. Orchestrator Multi-Session Support

- [ ] 3.1 Update `InstantShareReceiverOrchestrator` to accept `session_id` in all handler methods (`handle_connection_config`, `handle_trust_handshake_received`, `handle_transfer_received`, etc.)
- [ ] 3.2 Add per-session timeout tracking: replace single timeout timer with per-session timers keyed by `session_id`
- [ ] 3.3 Update lifecycle event publishing to include `session_id` in the `instant_share.lifecycle` event payload
- [ ] 3.4 Update `handle_delivery_complete()` to clean up only the specified session's resources (timers, temp files)
- [ ] 3.5 Remove any single-session assumptions in orchestrator (e.g., `replace_active_session` call during revisit)

## 4. HTTP Route / Handler Updates

- [ ] 4.1 Update `https_bootstrap.py` trust routes (`/trust/handshake`, `/trust/apply`, `/trust/confirm`) to extract `X-Session-Id` header and route to correct `TrustSessionRegistry` entry
- [ ] 4.2 Update `https_tls_server.py` transfer routes (`/transfer/text`, `/transfer/image`, `/transfer/download`) to extract `X-Session-Id` header and route to correct session
- [ ] 4.3 Update revisit transfer handling: on-the-fly session creation for `/transfer/*` when no matching session exists but client cert is trusted
- [ ] 4.4 Update `https_bootstrap.py` to return HTTP 503 (not 409) with `RECEIVER_BUSY_MAX_SESSIONS` when capacity is exceeded
- [ ] 4.5 Remove the `replace_active_session()` call in `https_bootstrap.py` that unconditionally replaced the active session

## 5. QR Trigger Handler Session Linking

- [ ] 5.1 Update `QRTriggerHandler` to store stash entries with correct `session_id` when other sessions are active
- [ ] 5.2 Ensure `/transfer/download` route correctly resolves stash by `stash_id` → `session_id` mapping under concurrent sessions
- [ ] 5.3 Verify stash expiry timers are independent and don't interfere with other sessions' lifecycle timers

## 6. Mini-Window UI — Independent Windows Per Session

- [ ] 6.1 Refactor mini-window creation: each session (pc-to-mobile or mobile-to-pc) creates its own independent window instead of sharing one
- [ ] 6.2 Associate each mini-window with its `session_id` so it only responds to lifecycle events for that session
- [ ] 6.3 Implement per-window status indicators: spinner (connecting), lock icon (negotiating), progress bar (transferring), checkmark (delivered), red X (error)
- [ ] 6.4 Set window title dynamically per direction: "Receiving from <device_name>" (mobile-to-pc) or "Sending to Phone" (pc-to-mobile)
- [ ] 6.5 Wire lifecycle events to windows: each window subscribes to `instant_share.lifecycle` events and filters by its own `session_id`
- [ ] 6.6 Implement per-window auto-close: window shows terminal state then auto-closes after 4s (success) / 10s (error)
- [ ] 6.7 Ensure QR stash windows (pc-to-pc) coexist correctly with transfer windows — each in its own window
- [ ] 6.8 Verify multiple windows can be opened, positioned, and dismissed independently without interfering

## 7. Integration & Edge Cases

- [ ] 7.1 Test: concurrent trust handshakes from two mobile devices — both complete independently
- [ ] 7.2 Test: QR stash created while mTLS transfer is active — each session gets its own independent mini-window
- [ ] 7.3 Test: revisit transfer during active trust handshake — on-the-fly session created alongside
- [ ] 7.4 Test: capacity limit — 9th session bootstrap returns 503; session frees when one completes
- [ ] 7.5 Test: stale terminal session cleanup — sessions removed 60s after reaching terminal state
- [ ] 7.6 Test: single session behavior unchanged — backward compatible, no regression in existing flow
- [ ] 7.7 Remove `RECEIVER_BUSY_SINGLE_SESSION` from `ErrorCode` enum and all references
- [ ] 7.8 Verify mobile clients (iOS) require zero changes — existing `X-Session-Id` header usage is sufficient
