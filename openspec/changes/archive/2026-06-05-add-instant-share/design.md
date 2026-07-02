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
- Maintain always-on discoverability via desktop mDNS (Bonjour) advertisement daemon for instant sharing.
- Ship production-quality instant-share UI on both mobile and desktop as part of this implementation slice.
- Desktop instant-share UI lives in a standalone mini window, completely independent from the main AuSearch app.
- Keep the iOS Share Extension handling the full flow natively (no AuBackup handoff): payload preflight, mDNS discovery, production device selector card, trust handshake/apply/confirm, and upload — all within the extension.
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
- Decision: Implement mDNS discovery, trust establishment, and transfer negotiation for instant sharing without depending on backup-session capability exchange endpoint.
- Rationale: Existing capability exchange endpoint is only available during QR backup session and does not fit instant-share entrypoint.
- Alternative considered: Reusing backup pairing/session/capability exchange.
- Why not: Lifecycle mismatch, hidden coupling, and inability to initiate from Share Extension flow.

2. Introduce a desktop Instant Receive Orchestrator as a thin integration layer.
- Decision: Add coordinator and related services under `dt_image_search/instant_sharing` that listen for instant-share requests, emit event-bus notification events, and route payloads to target writers (clipboard/file).
- Rationale: Preserves separation of concerns between transport, UI activation, and delivery side-effects, and avoids modifying desktop code in `dt_image_search/mobile/*`.
- Alternative considered: Handle everything in existing UI controllers.
- Why not: Increases UI/business coupling and thread-safety risk.

3. Introduce a desktop background mDNS advertisement daemon.
- Decision: Run an always-on desktop daemon process under instant-sharing domain to advertise one Bonjour service `_instantshare._tcp` with TXT records carrying:
	- `device_name` (human-readable PC name)
	- `device_id` (persistent unique identifier)
	- `signature` (cryptographic signature for trusted-direct verification — **deferred**, currently populated with placeholder)
	- `signature_key_id` (key identifier for signature verification — deferred)
	- `timestamp_ms` (signature freshness — deferred)
	- `ver` (protocol version)
- Rationale: Mobile must discover candidate PCs before send even when backup session is not active. mDNS (Bonjour) provides fast LAN-local discovery without the async state machine complexity of BLE, making it compatible with the iOS Share Extension's constrained execution window.
- Alternative considered: BLE GATT service with three characteristics (DeviceName, DeviceSignature, ConnectionConfig).
- Why not: BLE's `CBCentralManager` async state machine (`poweredOn` → scan → `didDiscover`) has unpredictable latency incompatible with Share Extension's short execution window. mDNS resolution completes in 100-300ms on LAN with no permission chain dependencies.

4. Bootstrap data merged into trust handshake (dedicated bootstrap endpoint removed).
- Decision: No dedicated `/sessions/bootstrap` endpoint. Bootstrap metadata (mobile_port, mobile_ip_list, payload_class, target_intent, trust_mode) is embedded in the `/trust/handshake` request body. Session creation happens when PC receives the handshake.
- Rationale: With the trust-flow direction inverted (iOS calls PC), the handshake is the natural first request. Merging bootstrap data eliminates an extra round-trip and simplifies the extension's sequential flow.
- History: The original design had a dedicated bootstrap POST (replacing BLE `ConnectionConfig` write). This was removed in the `pc-hosted-trust-and-upload` architecture inversion.

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

10. Session-id signature verification — **deferred**.
- Decision: Not implemented in current phase. X509 certificate exchange, session-id signature headers, mDNS TXT signature verification, and cert-pinned HTTPS trust are all deferred to a future iteration.
- Rationale: Current implementation uses AES-GCM trust envelope encryption with the session-derived key for confidentiality. The plain HTTP transport is considered acceptable for LAN-local v1 given the one-shot nature of instant-share sessions.
- Alternative considered: Require mTLS or session-id signature verification.
- Why not: Higher implementation overhead; deferred to simplify and ship v1.

13. Instant Share lives in a separate window, not embedded in the main AuSearch app.
- Decision: The instant-share desktop receive UI is implemented as a standalone mini window with its own window lifecycle, independent from the main AuSearch application window. The mini window does not share UI surface, navigation, tab state, or panel layout with backup, browser, or search features.
- Rationale: Keeps instant-share completely decoupled from existing features. The mini window can be created/destroyed on demand without affecting main app state. Simplifies development and testing by avoiding cross-feature UI dependencies.
- Alternative considered: Embed instant-share as a panel or tab inside the main AuSearch window.
- Why not: Coupling to main app navigation would risk disrupting existing features and complicates the instant-share lifecycle (e.g., user switches tabs mid-transfer).

14. Mini window triggered from background daemon via event bus + MainThreadDispatcher.
- Decision: The mini window is created by an `InstantShareMiniWindowFactory` that subscribes to the `INSTANT_SHARE_LIFECYCLE_EVENT` event bus directly (not through MainWindow). When the background daemon receives a bootstrap HTTP POST, the orchestrator publishes the lifecycle event, and the factory uses the existing `MainThreadDispatcher` to safely create and show the `QDialog`-based mini window on the Qt main thread. This works whether MainWindow is open or not.
- Rationale: The daemon runs in background threads (bootstrap HTTP server, orchestrator). Creating a Qt window directly from those threads is unsafe. The established `dispatcher.post()` pattern provides thread-safe main-thread dispatching without coupling to MainWindow's Signal/Slot infrastructure. The factory's independent event bus subscription means the mini window works even before MainWindow exists or after it's closed.
- Alternative considered: Add signals to MainWindow and require it to be open.
- Why not: The daemon receives bootstrap calls independently; the mini window must appear regardless of whether the user has the main search window open.

11. **Inverted**: PC hosts endpoints, iOS acts as HTTP client.
- Decision: The `pc-hosted-trust-and-upload` change inverted the architecture. PC hosts all trust and upload endpoints on port 9527. iOS calls PC's endpoints sequentially. No iOS-hosted HTTP server.
- Rationale: iOS Share Extension becomes a simple sequential caller (no server, no long-poll). More reliable — iOS-initiated outbound HTTP is less likely to be blocked by network sandboxing. PC-only changes to `dt_image_search/instant_sharing` preserved.
- Originally: Mobile-hosted, PC-downloaded. Inverted for reliability and extension execution efficiency.

12. Share Extension handles full trust + upload natively without main-app handoff or local server.
- Decision: The iOS Share Extension performs the complete instant-share flow in-place: mDNS discovery → device selection → trust handshake (to PC) → apply (get PIN from PC) → confirm (user taps Confirm) → upload (to PC) → completion UI. No NWListener-based HTTP server, no dedicated bootstrap endpoint, no URL-based navigation to AuBackup.
- Rationale: iOS navigation from a Share Extension to its containing app is unreliable — the `UIApplication` responder chain is unavailable, `extensionContext.open(url)` is deprecated and inconsistently supported across iOS versions, and the user experience of switching apps mid-share is confusing. Handling everything in the extension keeps the flow atomic and predictable.
- Alternative considered: Hand off selected device and payload context to AuBackup main app via app-group persistence + URL scheme navigation.
- Why not: URL-based navigation from extensions is poorly supported by iOS system, leads to fragile responder-chain hacks, and creates a disjointed UX where the user bounces between apps.
- Mitigation: Extension requests additional execution time via `beginRequest(with:)` for trust establishment and upload. Text payloads complete in <5s; images complete in <15s. The extension shows clear progress, PIN confirmation, and completion states.

## Risks / Trade-offs

- [Large payloads may take long time and appear stalled] -> Mitigation: Always show progress plus explicit user actions to continue waiting or abort.
- [Desktop receive UX may be suboptimal if chosen without validation] -> Mitigation: Resolved — Variant B (standalone mini window) selected after mock review. Mini window is independent from main app to avoid cross-feature coupling.
- [Clipboard writes can conflict with user clipboard usage] -> Mitigation: Restrict auto-clipboard to text payloads and display overwrite notice + optional preference to disable.
- [Single-session model can delay subsequent shares] -> Mitigation: Show busy state and queue/retry guidance on sender.
- [Cross-platform filesystem constraints] -> Mitigation: Normalize names, sanitize unsafe characters, enforce path boundary checks, and fallback naming.
- [Session signature verification can be bypassed if headers are missing or key lookup fails open] -> **Deferred**: Session-id signature verification not implemented. Current security relies on session-key AES-GCM trust envelope encryption over LAN-local HTTP.
- [Share Extension handoff can lose payload or selected-device context] -> **Not applicable**: Share Extension handles the full flow natively — no AuBackup handoff needed.
- [mDNS discovery may not find PC if devices are on different subnets or multicast is blocked] -> Mitigation: Show production empty/unavailable states with guidance to check same-network connection; mDNS failure is deterministic and fast, unlike BLE which silently hangs.

## Migration Plan

1. Add dedicated instant-sharing discovery/trust/transfer protocol path (independent from backup session endpoints).
2. Implement desktop orchestrator and target writers under `dt_image_search/instant_sharing` behind feature flag.
3. Implement iOS Share Extension payload extraction, mDNS discovery, production device selector card, and full flow handling (no AuBackup handoff — extension does everything) for text/image inputs.
4. Implement desktop mDNS advertisement daemon for always-on candidate discovery.
5. Implement PC-hosted HTTP server with trust and upload endpoints (no dedicated bootstrap endpoint — bootstrap data merged into `/trust/handshake`).
6. Implement trust flow endpoints on PC: `/trust/handshake` (plain DH + bootstrap data), encrypted `/trust/apply` (PC returns PIN), and `/trust/confirm` (simple POST, no long-poll).
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
