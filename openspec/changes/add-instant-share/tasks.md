## 1. Protocol and Session Foundations

- [x] 1.1 Implement dedicated instant-share protocol endpoints for discovery/trust/transfer with flow id, payload class, target intent, and correlation id metadata, following `openspec/changes/add-instant-share/api-spec.md`.
- [x] 1.1a Add/update unit tests for protocol endpoint request/response contracts and metadata validation.
- [x] 1.2 Implement instant-share trust and negotiation flow independent from QR backup pairing/session and backup capability-exchange endpoints.
- [x] 1.2a Add/update unit tests for trust/negotiation state transitions and independence from backup-session paths.
- [x] 1.3 Add authenticated sender validation for instant-share initiation with explicit failure responses for untrusted requests.
- [x] 1.3a Add/update unit tests for trusted/untrusted sender validation outcomes.
- [x] 1.3b Implement session-id signature headers on PC requests and mobile-side verification using exchanged trusted public key.
- [x] 1.3c Add/update unit tests for missing signature, invalid signature, missing trusted key, and valid signature paths.
- [x] 1.4 Implement desktop background daemon BLE service with three characteristics: `DeviceName` (RO), `DeviceSignature` (RO), `ConnectionConfig` (WO).
- [x] 1.4a Add/update unit tests for BLE characteristic exposure and access mode enforcement.
- [x] 1.5 Implement session bootstrap via BLE `ConnectionConfig` write (session id + mobile port + mobile ip list).
- [x] 1.5a Add/update unit tests for `ConnectionConfig` parsing/validation and bootstrap error handling.
- [x] 1.6 Implement trust APIs as `/trust/handshake`, encrypted `/trust/apply`, and parallel long-poll `/trust/confirm` with key exchange completion.
- [x] 1.6a Add/update unit tests for trust API crypto envelope handling and confirm long-poll completion semantics.

## 2. iOS Share Extension Ingest

- [x] 2.1 Implement Share Extension payload extractor for text, image, video, and other file inputs with normalized envelope creation.
- [x] 2.1a Add/update unit tests for payload normalization across text/image/video/file inputs.
- [x] 2.2 Add extension preflight checks for payload readability and metadata completeness before negotiation starts.
- [x] 2.2a Add/update unit tests for preflight pass/fail conditions.
- [x] 2.3 Implement unsupported-type rejection UX and error reporting in extension flow.
- [x] 2.3a Add/update unit tests for unsupported-type rejection mapping and error payload construction.
- [x] 2.4 Implement production Share Extension device selector card that lists discovered BLE PCs with usable device identity and trust-state affordances.
- [x] 2.4a Add/update tests for selector view-model state: scanning, empty, discovered, stale/expired device, trusted revisit, and first-use states.
- [x] 2.5 Implement selected-device and payload-context handoff from Share Extension to AuBackup main app for both first use and trusted revisits.
- [x] 2.5a Add/update tests for handoff context persistence, stale/missing context handling, and main-app resume routing.

## 3. Desktop Instant Receive Orchestration

- [x] 3.1 Implement desktop instant receive orchestrator under `dt_image_search/instant_sharing` that subscribes to incoming instant-share sessions and emits lifecycle events.
- [x] 3.1a Add/update unit tests for orchestrator subscription and lifecycle-event emission behavior.
- [x] 3.2 Wire orchestrator lifecycle states (`queued`, `negotiating`, `transferring`, `delivering`, `done|failed|timed_out`) onto event bus messages.
- [x] 3.2a Add/update unit tests for event bus state mapping and message payload schema.
- [x] 3.3 Produce two desktop receive UX mock sets: (A) notification-only, (B) click notification entry opens AuSearch.
- [x] 3.4 Run UX review and record final selection for runtime behavior.
- [ ] 3.5 Implement production desktop receive UX behavior based on selected variant, including progress, result, failure, and user-aborted states.
- [ ] 3.5a Add/update unit tests for selected-variant branching and non-visual receive UI controller/view-model logic.

## 4. Target Delivery Implementation

- [x] 4.1 Implement clipboard writer path for text payload delivery (clipboard only) with completion/failure signaling.
- [x] 4.1a Add/update unit tests for clipboard delivery success/failure signaling.
- [x] 4.2 Implement image dual-target delivery (clipboard or file) and video/other-file local-file-only delivery with sanitized deterministic filename generation and collision handling.
- [x] 4.2a Add/update unit tests for target selection rules, filename sanitization, and collision resolution.
- [x] 4.3 Enforce receive-directory boundary checks and reject unsafe path resolutions with explicit errors.
- [x] 4.3a Add/update unit tests for safe/unsafe path resolution cases.
- [x] 4.4 Set default local-file target path to user Downloads folder when no explicit directory is configured.
- [x] 4.4a Add/update unit tests for default directory fallback behavior.

## 5. Production Mobile and Desktop UI

- [x] 5.1 Implement production mobile instant-share UX in AuBackup for handoff resume, first-use trust confirmation, trusted-device revisit, progress, error, success, and abort/result states.
- [x] 5.2 Implement production Share Extension selector card visual states for scanning, empty/no receiver, discovered devices, selected device, and unavailable Bluetooth/permission states.
- [ ] 5.3 Implement production desktop instant-share UX for the selected receive variant with clear queued, transferring, delivering, success, failure, timeout, busy, and user-aborted states.
- [ ] 5.4 Validate end-to-end production UI behavior across Share Extension, AuBackup main app, and desktop receive surfaces.
- [x] 5.5 Add/update unit tests for non-visual UI state reducers/controllers/view-models introduced for production UI.

## 6. Reliability and Recovery

- [x] 6.1 Implement bounded retry with exponential backoff for transient negotiation/transfer failures.
- [x] 6.1a Add/update unit tests for retry limits, backoff intervals, and retryable error classification.
- [x] 6.2 Implement timeout thresholds and final state mapping for exhausted retry attempts.
- [x] 6.2a Add/update unit tests for timeout threshold handling and terminal-state mapping.
- [x] 6.3 Enforce single active instant-share session handling (reject/defer concurrent requests).
- [x] 6.3a Add/update unit tests for concurrent session rejection/deferral behavior.
- [x] 6.4 Add user-visible wait/abort controls for long transfers and surface user-aborted outcomes in desktop and iOS states.
- [x] 6.4a Add/update unit tests for wait/abort state transitions and user-aborted outcome propagation.

## 7. Telemetry and Observability

- [x] 7.1 Add span-first tracing for instant-share lifecycle with correlation id propagation across iOS and desktop components.
- [x] 7.1a Add/update unit tests for telemetry context propagation and required span attributes.
- [x] 7.2 Add key lifecycle events (session accepted, transfer start, delivery complete, failure reason) using standardized telemetry attributes.
- [x] 7.2a Add/update unit tests for lifecycle event emission and attribute completeness.
- [x] 7.3 Add sampling guardrails for high-volume transfer events to avoid telemetry overload.
- [x] 7.3a Add/update unit tests for telemetry sampling decision logic.

## 8. Integration and Functional Validation

- [x] 8.1 Add integration tests for authenticated negotiation, auto-activation, and target delivery outcomes.
- [x] 8.2 Add functional tests for end-to-end instant-share scenarios: text-to-clipboard, photo-to-file, video-to-file, and unreachable-PC failure.
- [x] 8.3 Run a regression sweep to ensure per-task unit tests are added/updated for every applicable code change.

## 10. iOS Debug UI and BLE/HTTPS Server (manual test path)

- [x] 10.1 Implement `InstantShareBLEScanner` (`CBCentralManager` wrapper that scans for the instant-share service UUID, exposes `discovered` peripherals, and publishes scanner state).
- [x] 10.2 Implement `InstantShareBLEPeripheralConnector` (connects to a selected peripheral, discovers the instant-share GATT service, and writes the `ConnectionConfig` payload).
- [x] 10.3 Implement `InstantShareTrustSessionManager` (X25519 ECDH + HKDF-SHA256 session key derivation that matches `X25519TrustSessionKeyResolver` on the PC, so the AES-GCM trust envelope unwraps on both sides).
- [x] 10.4 Implement `InstantShareHTTPServer` (`NWListener` with TLS using the bundled P12 identity, all 6 protocol endpoints, request/response parser, and request-id/correlation-id propagation).
- [x] 10.5 Implement `InstantShareService` orchestrator that owns scanner, server, and trust session state; publishes `statusLog`, `sharedPayload`, and `lastError`; and exposes `startDiscovery`, `selectPeripheral`, `updateConfig`, `startSession`, `stopSession`.
- [x] 10.6 Add `instantShareService` to `Container+App.swift` Factory DI and add `NSBluetoothAlwaysUsageDescription` to `App/Info.plist`.
- [x] 10.7 Rewrite `InstantShareDebugViewModel` and `InstantShareDebugView` for the full discovery → select → connect → config → start → PIN display flow.
- [x] 10.8 Build iOS app for iPhone 17 Pro Max simulator without errors.
- [x] 10.9 Add iOS unit tests for `InstantShareTrustSessionManager` key derivation and `InstantShareHTTPServer` request parser.
- [x] 10.10 Add PC CLI script `dt_image_search/scripts/start_instant_share_runtime.py` to launch the BLE + HTTP runtime for manual testing.
- [ ] 10.11 Manual e2e test: run PC CLI, open iOS debug view, scan, select PC, write config, verify trust handshake, verify text/photo transfer.

## 9. Rollout and Safeguards

- [x] 9.1 Gate instant-share feature behind a configuration flag and add safe default-off behavior.
- [x] 9.2 Define staged enablement checklist and rollback procedure using feature flag disable path.
- [x] 9.3 Update operator/developer docs for setup, user-facing behavior, troubleshooting, and known limits.
