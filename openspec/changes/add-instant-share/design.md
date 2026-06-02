## Context

Protocol reference:
- `openspec/changes/add-instant-share/api-spec.md` defines endpoint contracts, metadata schema, state transitions, and error model for task 1.1 implementation.

AuSearch and AuBackup currently support rich transfer and backup workflows, but not a low-friction "share and forget" path starting from iOS Share Extension. The new feature must bridge iOS extension constraints, existing mobile/PC pairing and transfer channels, and desktop UX activation in a way that feels immediate and deterministic.

Constraints:
- iOS Share Extension has strict execution/memory limits and limited background runtime.
- Payload sizes vary in the current slice across text and images, with video and other-file handling deferred to follow-up work.
- PC app can be running, minimized, or not currently focused.

Stakeholders:
- End users: fast one-tap share from iOS share sheet.
- Desktop/mobile engineering: robust cross-device transfer semantics.
- Support/ops: diagnosable failures and clear user-facing states.

## Goals / Non-Goals

**Goals:**
- Enable iOS Share Extension to initiate instant-share for text and images in the current implementation slice, with video and other file support deferred to a follow-up phase.
- Maintain always-on discoverability via desktop BLE broadcast daemon for instant sharing.
- Ship production-quality instant-share UI on both mobile and desktop as part of this implementation slice.
- Desktop instant-share UI lives in a standalone mini window, completely independent from the main AuSearch app.
- Keep the iOS Share Extension lightweight by limiting it to payload preflight, BLE discovery, and a production device selector card, then handing selected device and payload context to AuBackup main app.
- Deliver text to clipboard only and deliver images to clipboard or local files with predictable naming and status reporting in the current slice.
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
- Decision: Remove `/sessions` dependency. Session is created by AuBackup after it resumes Share Extension handoff context and is written to PC through BLE `ConnectionConfig` (mobile IP list, port, session ID).
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

7. Desktop receive UX finalized as Variant B — standalone mini window.
- Decision: Instant Share on desktop uses a standalone mini window (Variant B), independent from the main AuSearch app. The mini window is a dedicated 360x520px surface with its own title bar, traffic lights, and lifecycle. It opens on demand when an incoming share arrives and closes after completion. Completely separate from existing backup, browser, and search features.
- Rationale: Provides explicit visual confirmation and control for the transfer workflow without coupling to the main app's navigation or tab state. Users get a focused, task-specific surface that does not disrupt their current workflow in AuSearch.
- Alternative considered: Variant A (notification-only) and embedding inside AuSearch main window.
- Why not: Notification-only lacks progress visibility and user control for larger transfers. Embedding in AuSearch couples instant-share to existing UI navigation and risks disrupting backup/browser/search flows.

8. Single-session transfer model with user-controlled wait/abort.
- Decision: Do not support concurrent instant-share sessions. Queue/reject new incoming requests while one session is active. Do not reject transfers based on file size; allow user to keep waiting or abort.
- Rationale: Simplifies correctness and UX while honoring user control for long transfers.
- Alternative considered: Concurrent sessions and/or size-based pre-reject.
- Why not: Adds race complexity and may prematurely block legitimate large transfers.

9. Production UI implementation strategy (mobile + desktop).
- Decision: Build production-quality UI surfaces directly for instant-share selection, handoff, confirmation, progress, success, failure, and abort states.
- Rationale: The protocol has matured enough that temporary validation UI would create throwaway work and risk mismatched behavior between validation and release.
- Alternative considered: Deferring final visual and interaction quality until after functional validation.
- Why not: The feature is now targeting production readiness, and the Share Extension selector card is part of the user-facing contract.

10. Use session-id signature verification as the immediate client authentication layer.
- Decision: Do not require mTLS in this phase. Require PC to sign session id with its private key on each HTTP request, and require mobile to verify the signature with exchanged trusted PC public key.
- Rationale: This provides a simple and fast-to-implement client authentication mechanism using trust material we already exchange.
- Alternative considered: Require mTLS for all trusted-direct traffic.
- Why not: Higher implementation overhead for this phase; can be added later as a transport hardening step.

13. Instant Share lives in a separate window, not embedded in the main AuSearch app.
- Decision: The instant-share desktop receive UI is implemented as a standalone mini window with its own window lifecycle, independent from the main AuSearch application window. The mini window does not share UI surface, navigation, tab state, or panel layout with backup, browser, or search features.
- Rationale: Keeps instant-share completely decoupled from existing features. The mini window can be created/destroyed on demand without affecting main app state. Simplifies development and testing by avoiding cross-feature UI dependencies.
- Alternative considered: Embed instant-share as a panel or tab inside the main AuSearch window.
- Why not: Coupling to main app navigation would risk disrupting existing features and complicates the instant-share lifecycle (e.g., user switches tabs mid-transfer).

11. Keep the current desktop slice mobile-hosted and PC-downloaded.
- Decision: After trust completes, PC remains the HTTP client and downloads shared text or image payloads from the iOS-hosted local HTTP service.
- Rationale: This matches the iOS Share Extension hosting model and keeps desktop work isolated to `dt_image_search/instant_sharing` without changing `dt_image_search/mobile/*`.
- Alternative considered: Desktop-hosted ingestion endpoints that accept pushed payload bodies.
- Why not: That contradicts the current iOS-hosted server requirement and would reintroduce coupling to the existing desktop mobile-folder transport path.

12. Share Extension hands selected device to AuBackup for handling.
- Decision: The iOS Share Extension discovers BLE receivers and renders the production selector card, but tapping a device opens AuBackup main app with selected receiver identity, trust hints, and payload context. AuBackup then performs first-share trust, trusted-direct revisit handling, BLE `ConnectionConfig` bootstrap, local HTTP hosting, and transfer lifecycle UI.
- Rationale: Share Extension runtime is constrained; discovery and selection are user-facing and extension-appropriate, while trust, long-poll confirmation, HTTPS serving, retry, and delivery-result handling are better owned by the main app.
- Alternative considered: Complete trust and transfer inside the Share Extension after device selection.
- Why not: Extension lifetime and background constraints make the full trust/transfer lifecycle fragile, especially for first use and slower image transfers.

## Risks / Trade-offs

- [Large payloads may take long time and appear stalled] -> Mitigation: Always show progress plus explicit user actions to continue waiting or abort.
- [Desktop receive UX may be suboptimal if chosen without validation] -> Mitigation: Resolved — Variant B (standalone mini window) selected after mock review. Mini window is independent from main app to avoid cross-feature coupling.
- [Clipboard writes can conflict with user clipboard usage] -> Mitigation: Restrict auto-clipboard to text payloads and display overwrite notice + optional preference to disable.
- [Single-session model can delay subsequent shares] -> Mitigation: Show busy state and queue/retry guidance on sender.
- [Cross-platform filesystem constraints] -> Mitigation: Normalize names, sanitize unsafe characters, enforce path boundary checks, and fallback naming.
- [Session signature verification can be bypassed if headers are missing or key lookup fails open] -> Mitigation: Enforce fail-closed validation and explicit errors for missing/invalid signatures or missing trusted keys.
- [Share Extension handoff can lose payload or selected-device context] -> Mitigation: Persist handoff context through app-group storage or equivalent extension-safe mechanism before opening AuBackup, and make AuBackup fail closed with a clear recovery state if context is missing or stale.
- [BLE scanning from Share Extension may be constrained by iOS extension runtime, permissions, or short execution windows] -> Mitigation: Validate on physical devices early, show production permission/unavailable states, and fall back to opening AuBackup for discovery only if extension-level discovery cannot complete reliably.

## Migration Plan

1. Add dedicated instant-sharing discovery/trust/transfer protocol path (independent from backup session endpoints).
2. Implement desktop orchestrator and target writers under `dt_image_search/instant_sharing` behind feature flag.
3. Implement iOS Share Extension payload extraction, BLE discovery, production device selector card, and AuBackup handoff path for text/image inputs.
4. Implement desktop BLE broadcast daemon for always-on candidate discovery.
5. Implement BLE `ConnectionConfig` session bootstrap and remove `/sessions` endpoint dependency.
6. Implement trust flow endpoints: `/trust/handshake`, encrypted `/trust/apply`, and long-poll `/trust/confirm`.
7. Finalize desktop receive UX: Variant B selected — standalone mini window independent from AuSearch main app.
8. Implement production mobile and desktop UX surfaces wired via event bus and mobile state models.
9. Enforce single active instant-share session handling.
10. Enable telemetry spans/events for end-to-end success/failure/user-abort analysis.
11. Roll out with default-off internal testing, then staged enablement.

Rollback strategy:
- Disable feature flag to bypass instant-share entrypoints while keeping core backup/search flows unchanged.
- Preserve compatibility by ignoring unknown instant-share metadata on older endpoints.

## Open Questions

Resolved decisions:
	- Desktop receive UX: Variant B selected — standalone mini window, independent from main AuSearch app.
	- Local file target default path is user Downloads folder.
	- No size-based rejection policy; user decides to keep waiting or abort transfer.
	- Text-to-file is out of scope; text target is clipboard only.
