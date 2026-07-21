## Why

The instant share launch agent currently enforces a strict single-session constraint (`RECEIVER_BUSY_SINGLE_SESSION`), blocking concurrent sharing from multiple mobile devices to the same PC. This prevents scenarios like two family members simultaneously sharing content, or one device completing a trust handshake while another transfers. The system must support multiple independent sessions concurrently — each with its own lifecycle, trust negotiation, and transfer state.

## What Changes

- **BREAKING**: Remove `RECEIVER_BUSY_SINGLE_SESSION` error — `bootstrap()` no longer rejects new sessions when others are active
- Refactor `InstantShareSessionRegistry` from a single `_active_session` slot to a `dict[session_id, InstantShareSession]` collection
- Refactor `TrustSessionRegistry` from a single `_session` slot to a `dict[session_id, TrustSession]` collection
- Update the orchestrator to track and drive multiple concurrent session lifecycles
- Update the HTTP server handlers to route requests to the correct session by `X-Session-Id`
- QR stash handler already supports multiple stashes via dict — ensure session linking stays correct under concurrency
- Mini-window UI must handle displaying multiple active sessions (show the most recent, allow cycling, or show a summary)
- Add a session capacity limit (configurable, default e.g. 8) to prevent unbounded resource consumption

## Capabilities

### New Capabilities

- `multi-session-registry`: Refactor session and trust registries to support multiple concurrent sessions with thread-safe CRUD operations, capacity limits, and idempotent request routing
- `multi-session-orchestrator`: Update orchestrator to manage multiple concurrent session lifecycles, publishing independent lifecycle events per session
- `multi-session-ui`: Update the mini-window UI to display and manage multiple active sessions simultaneously

### Modified Capabilities

- `pc-revisit-session`: Remove the `RECEIVER_BUSY_SINGLE_SESSION` constraint on revisit transfers; on-the-fly sessions coexist with other active sessions
- `launch-agent-qr-display`: QR stashes (already dict-based) must correctly coexist with other sessions without session-linking conflicts
- `instant-share-secure-discovery-trust`: Trust handshake endpoints must correctly associate with the requesting session via `X-Session-Id` when multiple sessions are active

## Impact

- **Affected code**: `dt_image_search/instant_sharing/session.py` (registry), `trust_server.py` (TrustSessionRegistry), `orchestrator.py` (lifecycle management), `https_bootstrap.py` and `https_tls_server.py` (request routing), QR trigger handler (session linking), mini-window (UI)
- **Affected specs**: `pc-revisit-session`, `launch-agent-qr-display`, `instant-share-secure-discovery-trust`
- **No API changes to external clients**: HTTP endpoints remain the same; mobile clients already send `X-Session-Id`
- **No database schema changes**: Sessions are in-memory only
