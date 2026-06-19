## Context

The instant share launch agent on PC currently enforces a strict single-session constraint: `InstantShareSessionRegistry` holds exactly one `_active_session` slot, `TrustSessionRegistry` holds one `_session` slot, and any concurrent sharing attempt from a different mobile device is rejected with `RECEIVER_BUSY_SINGLE_SESSION` (HTTP 409). The QR trigger handler (`QRTriggerHandler`) already uses a `dict[str, StashEntry]` for stashes — but stashes are linked to a single session via `_session_ids: dict[str, str]`.

This design refactors the session management primitives to support N concurrent sessions, each with its own lifecycle, trust negotiation, and transfer state.

### Current architecture
- `InstantShareSessionRegistry` → single `Optional[InstantShareSession]`
- `TrustSessionRegistry` → single `Optional[TrustSession]`
- `QRTriggerHandler` → `dict[str, StashEntry]` (already multi) + `dict[str, str]` stash→session link
- `InstantShareReceiverOrchestrator` → drives a single session state machine
- Mini-window → displays one session at a time
- HTTP routes (`https_bootstrap.py`, `https_tls_server.py`) → route to orchestrator which assumes single session
- `_ACTIVE_STATES` set in `session.py` determines which states block new sessions

## Goals / Non-Goals

**Goals:**
- Support up to N concurrent instant share sessions (default N=8)
- Each session has independent lifecycle, trust state, and transfer progress
- QR stash sessions coexist with mTLS transfer sessions
- Multiple trust handshakes can proceed concurrently
- Each session runs in its own independent mini-window (pc-to-mobile or mobile-to-pc)
- No API changes to mobile clients (they already send `X-Session-Id`)

**Non-Goals:**
- Changing the existing mini-window widget design (new windows reuse existing layout widgets)
- Changing the trust protocol (DH exchange, PIN flow, certificate exchange)
- Session persistence across app restarts (sessions remain in-memory)
- Dynamic capacity adjustment (capacity is set once at init)
- Load balancing or session prioritization

## Decisions

### Decision 1: Dict-based registry instead of ordered container
**Choice**: `dict[session_id, InstantShareSession]` with thread-safe RLock, not `list` or `OrderedDict`.

**Rationale**: `session_id` is the universal lookup key — mobile clients already send `X-Session-Id` in every request. Dict gives O(1) lookup by key. No ordering requirements for sessions (the mini-window can sort by `started_monotonic` when needed). RLock instead of Lock because `transition()` might need to call back into the registry in future (reentrant safety).

**Alternative considered**: `OrderedDict` for insertion-order iteration. Rejected — mini-window should sort by last-updated, not insertion order. Adding a `last_updated` field to `InstantShareSession` is cleaner.

### Decision 2: Capacity limit with 503 response
**Choice**: Hard limit of 8 concurrent non-terminal sessions, enforced at `bootstrap()`, returning `RECEIVER_BUSY_MAX_SESSIONS` (HTTP 503).

**Rationale**: Unbounded sessions risk memory exhaustion (each session has thread timers, temp file handles, DH key material). 8 is generous for household use (family sharing). 503 is the standard "service overloaded, retry later" HTTP status. The error is retryable so mobile clients can poll.

**Alternative considered**: No limit. Rejected — even though Python can handle many threads, each session's TLS connection + trust material + file handles adds up. An explicit limit is safer.

### Decision 3: Keep _ACTIVE_STATES for state filtering, not blocking
**Choice**: Retain `_ACTIVE_STATES` as a filter predicate for `get_active_sessions()` rather than as a gate for new session creation.

**Rationale**: The `_ACTIVE_STATES` set is useful for deciding which sessions to display in the mini-window and which to count against the capacity limit. It should no longer block `bootstrap()`. The unchanged states are `{BOOTSTRAPPED, QUEUED, NEGOTIATING, TRANSFERRING, DELIVERING}`.

### Decision 4: Terminal session TTL cleanup via per-session timer
**Choice**: Each session that enters a terminal state (`DONE`, `FAILED`, `TIMED_OUT`, `ABORTED`) gets a 60-second oneshot timer; when it fires, the session is removed from the registry.

**Rationale**: Follows the existing pattern of oneshot timers per stash in `QRTriggerHandler`. Prevents memory leaks from accumulated terminal sessions. 60 seconds gives the mini-window time to display "Delivered" or error states before the session card is removed.

**Alternative considered**: Periodic cleanup loop scanning all sessions. Rejected — oneshot timers are more efficient (no scanning) and consistent with the existing stash-expiry pattern.

### Decision 5: Independent mini-windows per session (not a shared tabbed window)
**Choice**: Each session (pc-to-mobile or mobile-to-pc) gets its own independent mini-window. No shared window, no tab selector.

**Rationale**: This matches the existing single-session window pattern — each session simply opens its own window. Independent windows let the user arrange them on screen, dismiss individual sessions, and clearly see which device is involved. Qt's window management handles positioning; there's no need for a custom tab widget. Each window subscribes to lifecycle events filtered by `session_id`, so it only updates for its own session.

**Alternative considered**: Single window with horizontal tabs. Rejected — tabs require custom UI work, constrain positioning, and make it harder to see multiple sessions at once. Independent windows are simpler to implement and more flexible for the user.

### Decision 6: No changes to mobile clients
**Choice**: Mobile clients (iOS Share Extension, AuBackup app) require zero changes.

**Rationale**: Mobile clients already:
1. Generate their own `X-Session-Id` (UUID v4) as required by `revisit-transfer-skip-trust`
2. Send `X-Session-Id` in trust and transfer requests
3. The `RECEIVER_BUSY_SINGLE_SESSION` response is removed — the mobile retry logic for 409 can remain unchanged (it will just never receive 409 for this reason; 503 is a different code)

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| Thread contention on registry RLock under high concurrency | RLock is fine for 8 sessions; Python GIL already serializes; if observed, switch to per-session locks |
| Too many mini-windows clutter the desktop | 8-session capacity keeps window count manageable; user can dismiss windows individually |
| Stale session accumulation if cleanup timer fails | Registry size is bounded by capacity (8); worst case is 8 terminal sessions kept for 60s = negligible memory |
| Trust session key material memory exposure | DH material is already short-lived (session TTL); no change to key lifecycle |
| QR stash session-linking breaks under concurrency | QR stash→session link is 1:1 via `_session_ids[stash_id]` dict; no cross-session interference |
| `bootstrap_revisit()` currently replaces `_active_session` unconditionally | Refactored to create independent sessions — revisit sessions no longer overwrite anything |

## Open Questions

- **Q1**: Should the capacity limit be user-configurable in settings? → Defer — default of 8 is generous, revisit if user feedback demands it.
- **Q2**: Should sessions from the same device (same client cert CN) replace each other? → No — each session is independent. If a device reconnects with a new `X-Session-Id`, it creates a new session.
- **Q3**: What about the `https_bootstrap.py` code that currently replaces the active session on MOBILE_TO_PC handshake? → This is the `replace_active_session()` call. It should be removed — instead, the handshake creates a new session associated with the mobile's `X-Session-Id`.
