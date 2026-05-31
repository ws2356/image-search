## 1. Protocol and Session Foundations

- [ ] 1.1 Implement dedicated instant-share protocol endpoints for discovery/trust/transfer with flow id, payload class, target intent, and correlation id metadata, following `openspec/changes/add-instant-share/api-spec.md`.
- [ ] 1.2 Implement instant-share trust and negotiation flow independent from QR backup pairing/session and backup capability-exchange endpoints.
- [ ] 1.3 Add authenticated sender validation for instant-share initiation with explicit failure responses for untrusted requests.
- [ ] 1.4 Implement desktop background daemon BLE service with three characteristics: `DeviceName` (RO), `DeviceSignature` (RO), `ConnectionConfig` (WO).
- [ ] 1.5 Implement session bootstrap via BLE `ConnectionConfig` write (session id + mobile port + mobile ip list).
- [ ] 1.6 Implement trust APIs as `/trust/handshake`, encrypted `/trust/apply`, and parallel long-poll `/trust/confirm` with key exchange completion.

## 2. iOS Share Extension Ingest

- [ ] 2.1 Implement Share Extension payload extractor for text, image, video, and other file inputs with normalized envelope creation.
- [ ] 2.2 Add extension preflight checks for payload readability and metadata completeness before negotiation starts.
- [ ] 2.3 Implement unsupported-type rejection UX and error reporting in extension flow.

## 3. Desktop Instant Receive Orchestration

- [ ] 3.1 Implement desktop instant receive orchestrator under `dt_image_search/instant_sharing` that subscribes to incoming instant-share sessions and emits lifecycle events.
- [ ] 3.2 Wire orchestrator lifecycle states (`queued`, `negotiating`, `transferring`, `delivering`, `done|failed|timed_out`) onto event bus messages.
- [ ] 3.3 Produce two desktop receive UX mock sets: (A) notification-only, (B) click notification entry opens AuSearch.
- [ ] 3.4 Run UX review and record final selection for runtime behavior.
- [ ] 3.5 Implement minimum viable desktop receive UX behavior based on selected variant for rapid flow bring-up.

## 4. Target Delivery Implementation

- [ ] 4.1 Implement clipboard writer path for text payload delivery (clipboard only) with completion/failure signaling.
- [ ] 4.2 Implement image dual-target delivery (clipboard or file) and video/other-file local-file-only delivery with sanitized deterministic filename generation and collision handling.
- [ ] 4.3 Enforce receive-directory boundary checks and reject unsafe path resolutions with explicit errors.
- [ ] 4.4 Set default local-file target path to user Downloads folder when no explicit directory is configured.

## 5. Mobile and Desktop UI Delivery Phases

- [ ] 5.1 Implement minimum viable mobile instant-share UX (selection, progress, error/result states) for end-to-end flow validation.
- [ ] 5.2 Validate end-to-end flow using MVP UI on both mobile and desktop.
- [ ] 5.3 Execute dedicated UI design and polish pass for mobile.
- [ ] 5.4 Execute dedicated UI design and polish pass for desktop.
- [ ] 5.5 Re-verify behavior parity after polish pass.

## 6. Reliability and Recovery

- [ ] 6.1 Implement bounded retry with exponential backoff for transient negotiation/transfer failures.
- [ ] 6.2 Implement timeout thresholds and final state mapping for exhausted retry attempts.
- [ ] 6.3 Enforce single active instant-share session handling (reject/defer concurrent requests).
- [ ] 6.4 Add user-visible wait/abort controls for long transfers and surface user-aborted outcomes in desktop and iOS states.

## 7. Telemetry and Observability

- [ ] 7.1 Add span-first tracing for instant-share lifecycle with correlation id propagation across iOS and desktop components.
- [ ] 7.2 Add key lifecycle events (session accepted, transfer start, delivery complete, failure reason) using standardized telemetry attributes.
- [ ] 7.3 Add sampling guardrails for high-volume transfer events to avoid telemetry overload.

## 8. Validation and Testing

- [ ] 8.1 Add unit tests for payload normalization, path sanitization, and retry policy behavior.
- [ ] 8.2 Add integration tests for authenticated negotiation, auto-activation, and target delivery outcomes.
- [ ] 8.3 Add functional tests for end-to-end instant-share scenarios: text-to-clipboard, photo-to-file, video-to-file, and unreachable-PC failure.

## 9. Rollout and Safeguards

- [ ] 9.1 Gate instant-share feature behind a configuration flag and add safe default-off behavior.
- [ ] 9.2 Define staged enablement checklist and rollback procedure using feature flag disable path.
- [ ] 9.3 Update operator/developer docs for setup, user-facing behavior, troubleshooting, and known limits.
