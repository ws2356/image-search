## Context

AuSearch and AuBackup currently support rich transfer and backup workflows, but not a low-friction "share and forget" path starting from iOS Share Extension. The new feature must bridge iOS extension constraints, existing mobile/PC pairing and transfer channels, and desktop UX activation in a way that feels immediate and deterministic.

Constraints:
- iOS Share Extension has strict execution/memory limits and limited background runtime.
- Media payloads vary greatly in size (text to large videos).
- PC app can be running, minimized, or not currently focused.
- Transfer path must reuse existing secure pairing/session primitives where possible.

Stakeholders:
- End users: fast one-tap share from iOS share sheet.
- Desktop/mobile engineering: robust cross-device transfer semantics.
- Support/ops: diagnosable failures and clear user-facing states.

## Goals / Non-Goals

**Goals:**
- Enable iOS Share Extension to initiate instant-share for text, screenshots, photos, and videos.
- Auto-activate a focused receive UX in AuSearch/AuBackup on PC when an instant-share arrives.
- Deliver text to clipboard and media to local files with predictable naming and status reporting.
- Ensure reliability with bounded retry, timeout, and recoverable error handling.

**Non-Goals:**
- Full album/library synchronization or background batch backup redesign.
- New cloud relay/storage architecture for offline delivery.
- Arbitrary file types beyond text/image/video in this change.
- Deep editing/transformation of shared media before receive.

## Decisions

1. Reuse existing pairing/session infrastructure with an Instant Share session profile.
- Decision: Extend capability exchange/session metadata to include `flow=instant_share`, payload type, byte-size hint, and target intent.
- Rationale: Keeps security model and discovery behavior consistent, minimizing protocol divergence.
- Alternative considered: Separate lightweight instant-share transport service.
- Why not: Adds duplicate connection lifecycle and more security surface.

2. Introduce a desktop Instant Receive Orchestrator as a thin integration layer.
- Decision: Add a coordinator in desktop mobile/transfer layer that listens for instant-share requests, emits event-bus activation events, and routes payloads to target writers (clipboard/file).
- Rationale: Preserves separation of concerns between transport, UI activation, and delivery side-effects.
- Alternative considered: Handle everything in existing UI controllers.
- Why not: Increases UI/business coupling and thread-safety risk.

3. Use staged receive states with idempotent completion semantics.
- Decision: Standardize states: `queued -> negotiating -> transferring -> delivering -> done|failed|timed_out` with a transfer/session correlation id.
- Rationale: Enables deterministic UX and telemetry/troubleshooting.
- Alternative considered: Binary success/fail only.
- Why not: Insufficient observability and poor recovery behavior.

4. Delivery policy by payload class.
- Decision: Text defaults to clipboard target; image/video defaults to file target under configured Instant Share directory (with timestamp + short hash filenames). Optional user preference can force text-to-file.
- Rationale: Aligns with user expectation for quick snippet use while preserving media assets.
- Alternative considered: Always prompt user for target at receive time.
- Why not: Adds interaction friction and breaks "share and forget" intent.

5. Bounded reliability policy tuned for quick interactions.
- Decision: Negotiate within short timeout window, perform small-number exponential retries, then surface failure and stop.
- Rationale: Fast feedback is better than long hidden retries for instant workflows.
- Alternative considered: Long-running retry queue.
- Why not: Better suited for backup/sync workflows, not instant-share UX.

## Risks / Trade-offs

- [Large video payloads may exceed extension runtime limits] -> Mitigation: Use metadata-first handshake and stream transfer path with early progress signal; fail fast with explicit guidance when limits are exceeded.
- [Auto-activation may feel intrusive on desktop] -> Mitigation: Use subtle focused panel/toast behavior with preference toggle for activation mode.
- [Clipboard writes can conflict with user clipboard usage] -> Mitigation: Restrict auto-clipboard to text payloads and display overwrite notice + optional preference to disable.
- [Concurrent instant-share sessions may race delivery targets] -> Mitigation: Per-session correlation id, serialized delivery writer for clipboard, and unique filenames for file targets.
- [Cross-platform filesystem constraints] -> Mitigation: Normalize names, sanitize unsafe characters, enforce path boundary checks, and fallback naming.

## Migration Plan

1. Add protocol/session metadata support for instant-share flow in backward-compatible form.
2. Implement desktop orchestrator and target writers behind feature flag.
3. Implement iOS Share Extension payload extraction and transfer trigger path.
4. Add desktop UX activation and status surfaces wired via event bus.
5. Enable telemetry spans/events for end-to-end success/failure analysis.
6. Roll out with default-off internal testing, then staged enablement.

Rollback strategy:
- Disable feature flag to bypass instant-share entrypoints while keeping core backup/search flows unchanged.
- Preserve compatibility by ignoring unknown instant-share metadata on older endpoints.

## Open Questions

- Should instant-share file target default path be shared with existing import location or a dedicated folder?
- What maximum payload size should be accepted for video before immediate reject?
- Should auto-activation behavior differ when app is in full-screen workflows?
- Is text-to-file preference needed in v1, or can it be deferred to a follow-up?
