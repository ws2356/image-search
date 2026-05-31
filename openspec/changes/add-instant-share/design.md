## Context

Protocol reference:
- `openspec/changes/add-instant-share/api-spec.md` defines endpoint contracts, metadata schema, state transitions, and error model for task 1.1 implementation.

AuSearch and AuBackup currently support rich transfer and backup workflows, but not a low-friction "share and forget" path starting from iOS Share Extension. The new feature must bridge iOS extension constraints, existing mobile/PC pairing and transfer channels, and desktop UX activation in a way that feels immediate and deterministic.

Constraints:
- iOS Share Extension has strict execution/memory limits and limited background runtime.
- Payload sizes vary greatly (text, images, videos, and other files).
- PC app can be running, minimized, or not currently focused.

Stakeholders:
- End users: fast one-tap share from iOS share sheet.
- Desktop/mobile engineering: robust cross-device transfer semantics.
- Support/ops: diagnosable failures and clear user-facing states.

## Goals / Non-Goals

**Goals:**
- Enable iOS Share Extension to initiate instant-share for text, screenshots, photos, videos, and other file types.
- Maintain always-on discoverability via desktop BLE broadcast daemon for instant sharing.
- Ship a minimum viable UI on both mobile and desktop quickly to validate end-to-end flow.
- Run a dedicated UI design and polish pass for both mobile and desktop after MVP flow validation.
- Finalize desktop receive UX after comparing two mock variants (notification-only vs notification-click-opens-AuSearch).
- Deliver text to clipboard only; deliver images to clipboard or local files; deliver videos/other files to local files with predictable naming and status reporting.
- Ensure reliability with bounded retry, single-session execution, and recoverable error handling.

**Non-Goals:**
- Full album/library synchronization or background batch backup redesign.
- New cloud relay/storage architecture for offline delivery.
- Large-media optimization strategies (chunk-level/adaptive tuning) in this iteration.
- Deep editing/transformation of shared media before receive.
- Text-to-file delivery in this iteration.

## Decisions

1. Use a dedicated Instant Sharing protocol path independent of QR backup pairing/session infrastructure.
- Decision: Implement BLE discovery, trust establishment, and transfer negotiation for instant sharing without depending on backup-session capability exchange endpoint.
- Rationale: Existing capability exchange endpoint is only available during QR backup session and does not fit instant-share entrypoint.
- Alternative considered: Reusing backup pairing/session/capability exchange.
- Why not: Lifecycle mismatch, hidden coupling, and inability to initiate from Share Extension flow.

2. Introduce a desktop Instant Receive Orchestrator as a thin integration layer.
- Decision: Add coordinator and related services under `dt_image_search/instant_sharing` that listen for instant-share requests, emit event-bus notification events, and route payloads to target writers (clipboard/file).
- Rationale: Preserves separation of concerns between transport, UI activation, and delivery side-effects, and avoids modifying desktop code in `dt_image_search/mobile/*`.
- Alternative considered: Handle everything in existing UI controllers.
- Why not: Increases UI/business coupling and thread-safety risk.

3. Introduce a desktop background BLE broadcast daemon.
- Decision: Run an always-on desktop daemon process under instant-sharing domain to expose one BLE service with three characteristics:
	- `DeviceName` (read-only)
	- `DeviceSignature` (read-only)
	- `ConnectionConfig` (write-only)
- Rationale: Mobile must discover candidate PCs before send even when backup session is not active.
- Alternative considered: Broadcast from UI process only when app window is active.
- Why not: Discovery reliability drops and flow depends on UI foreground state.

4. Session bootstrap via BLE instead of `/sessions` endpoint.
- Decision: Remove `/sessions` dependency. Session is created on mobile at device selection time and written to PC through BLE `ConnectionConfig` (mobile IP list, port, session ID).
- Rationale: Keeps session initiation coupled to physical device choice and reduces extra round-trip endpoint complexity.
- Alternative considered: HTTP `/sessions` create endpoint.
- Why not: Redundant with BLE bootstrap and less aligned with discovery-first flow.

5. Use staged receive states with idempotent completion semantics.
- Decision: Standardize states: `queued -> negotiating -> transferring -> delivering -> done|failed|timed_out` with a transfer/session correlation id.
- Rationale: Enables deterministic UX and telemetry/troubleshooting.
- Alternative considered: Binary success/fail only.
- Why not: Insufficient observability and poor recovery behavior.

6. Delivery policy by payload class.
- Decision: Text goes to clipboard only. Images can go to clipboard or local files. Videos and other files go to local files only. Local-file default location is user Downloads folder.
- Rationale: Aligns with user expectation for quick text use, keeps binary payload persistence explicit, and provides predictable default storage.
- Alternative considered: Always prompt user for target at receive time.
- Why not: Adds interaction friction and breaks "share and forget" intent.

7. Desktop receive UX finalization via mock comparison.
- Decision: Keep desktop receive UX unfinalized until two mock sets are reviewed:
	- Variant A: notification-only receive UX
	- Variant B: notification entry opens AuSearch for receive handling
- Rationale: UX tradeoff between low intrusion and explicit workflow handoff needs validation before locking behavior.
- Alternative considered: Lock notification-only immediately.
- Why not: Premature decision before UX review could reduce usability.

8. Single-session transfer model with user-controlled wait/abort.
- Decision: Do not support concurrent instant-share sessions. Queue/reject new incoming requests while one session is active. Do not reject transfers based on file size; allow user to keep waiting or abort.
- Rationale: Simplifies correctness and UX while honoring user control for long transfers.
- Alternative considered: Concurrent sessions and/or size-based pre-reject.
- Why not: Adds race complexity and may prematurely block legitimate large transfers.

9. Two-phase UI implementation strategy (mobile + desktop).
- Decision: Implement minimum viable UX first to validate protocol/transfer flow, then perform a dedicated design/polish pass.
- Rationale: Reduces time-to-first-working-flow while preserving room for quality UX refinement.
- Alternative considered: Full polished UX before flow validation.
- Why not: Slows functional validation and increases rework risk if protocol behavior changes.

## Risks / Trade-offs

- [Large payloads may take long time and appear stalled] -> Mitigation: Always show progress plus explicit user actions to continue waiting or abort.
- [Desktop receive UX may be suboptimal if chosen without validation] -> Mitigation: Produce and review two mock sets before behavior lock; add acceptance criteria per variant.
- [Clipboard writes can conflict with user clipboard usage] -> Mitigation: Restrict auto-clipboard to text payloads and display overwrite notice + optional preference to disable.
- [Single-session model can delay subsequent shares] -> Mitigation: Show busy state and queue/retry guidance on sender.
- [Cross-platform filesystem constraints] -> Mitigation: Normalize names, sanitize unsafe characters, enforce path boundary checks, and fallback naming.

## Migration Plan

1. Add dedicated instant-sharing discovery/trust/transfer protocol path (independent from backup session endpoints).
2. Implement desktop orchestrator and target writers under `dt_image_search/instant_sharing` behind feature flag.
3. Implement iOS Share Extension payload extraction and transfer trigger path for text/image/video/other files.
4. Implement desktop BLE broadcast daemon for always-on candidate discovery.
5. Implement BLE `ConnectionConfig` session bootstrap and remove `/sessions` endpoint dependency.
6. Implement trust flow endpoints: `/trust/handshake`, encrypted `/trust/apply`, and long-poll `/trust/confirm`.
7. Produce two desktop receive UX mock sets and finalize behavior.
8. Implement minimum viable mobile and desktop UX surfaces for flow bring-up.
9. Add finalized desktop receive UX and status surfaces wired via event bus.
10. Run dedicated mobile and desktop UI design/polish pass.
11. Enforce single active instant-share session handling.
12. Enable telemetry spans/events for end-to-end success/failure/user-abort analysis.
13. Roll out with default-off internal testing, then staged enablement.

Rollback strategy:
- Disable feature flag to bypass instant-share entrypoints while keeping core backup/search flows unchanged.
- Preserve compatibility by ignoring unknown instant-share metadata on older endpoints.

## Open Questions

- Desktop receive UX behavior is pending mock review. Options:
	- Variant A: full notification-only UX.
	- Variant B: click notification entry to open AuSearch for receive flow.

Resolved decisions:
	- Local file target default path is user Downloads folder.
	- No size-based rejection policy; user decides to keep waiting or abort transfer.
	- Text-to-file is out of scope; text target is clipboard only.
