## 1. Protocol and Session Foundations

- [ ] 1.1 Extend instant-share session metadata schema to include flow id, payload class, size hint, target intent, and correlation id.
- [ ] 1.2 Update capability exchange and negotiation handlers to accept `flow=instant_share` while preserving backward compatibility.
- [ ] 1.3 Add authenticated sender validation path for instant-share initiation and explicit failure responses for unpaired requests.

## 2. iOS Share Extension Ingest

- [ ] 2.1 Implement Share Extension payload extractor for text, image, and video inputs with normalized envelope creation.
- [ ] 2.2 Add extension preflight checks for payload readability, size policy, and metadata completeness before negotiation starts.
- [ ] 2.3 Implement unsupported-type rejection UX and error reporting in extension flow.

## 3. Desktop Instant Receive Orchestration

- [ ] 3.1 Implement desktop instant receive orchestrator that subscribes to incoming instant-share sessions and emits lifecycle events.
- [ ] 3.2 Wire orchestrator lifecycle states (`queued`, `negotiating`, `transferring`, `delivering`, `done|failed|timed_out`) onto event bus messages.
- [ ] 3.3 Add user preference handling for auto-focus vs notification-only activation behavior.

## 4. Target Delivery Implementation

- [ ] 4.1 Implement clipboard writer path for text payload delivery with completion/failure signaling.
- [ ] 4.2 Implement file writer path for image/video payloads with sanitized deterministic filename generation and collision handling.
- [ ] 4.3 Enforce receive-directory boundary checks and reject unsafe path resolutions with explicit errors.

## 5. Reliability and Recovery

- [ ] 5.1 Implement bounded retry with exponential backoff for transient negotiation/transfer failures.
- [ ] 5.2 Implement timeout thresholds and final state mapping for exhausted retry attempts.
- [ ] 5.3 Add fallback user-visible failure states and actionable retry guidance in desktop and iOS surfaces.

## 6. Telemetry and Observability

- [ ] 6.1 Add span-first tracing for instant-share lifecycle with correlation id propagation across iOS and desktop components.
- [ ] 6.2 Add key lifecycle events (session accepted, transfer start, delivery complete, failure reason) using standardized telemetry attributes.
- [ ] 6.3 Add sampling guardrails for high-volume transfer events to avoid telemetry overload.

## 7. Validation and Testing

- [ ] 7.1 Add unit tests for payload normalization, path sanitization, and retry policy behavior.
- [ ] 7.2 Add integration tests for authenticated negotiation, auto-activation, and target delivery outcomes.
- [ ] 7.3 Add functional tests for end-to-end instant-share scenarios: text-to-clipboard, photo-to-file, video-to-file, and unreachable-PC failure.

## 8. Rollout and Safeguards

- [ ] 8.1 Gate instant-share feature behind a configuration flag and add safe default-off behavior.
- [ ] 8.2 Define staged enablement checklist and rollback procedure using feature flag disable path.
- [ ] 8.3 Update operator/developer docs for setup, user-facing behavior, troubleshooting, and known limits.
