# Refactor dt_image_search/mobile/*
## Overall design
This refactor plan aims to abstract the transport layer and add a new transport for USB communication. The existing transport for Wi-Fi LAN will be refactored to fit into the new architecture.

The new transport layer logically work as a server that handles incoming requests (like pairing claiming, transfer start, transfer upload, transfer complete), routing them to upper layers like pairing_service and transfer_service, and sending responses back to the client.

The new transport physically work as an http server for Wi-Fi LAN and as a websocket client for USB. The transport layer defines a common message schema which will be used by mobile side and desktop side to communicate. For development speed, let's use JSON as the message format for now, and we can switch to protobuf later if needed.

## Concrete refactor objectives
1. Keep current LAN behavior 100% compatible while extracting transport concerns.
2. Introduce a transport-agnostic routing layer so pairing/transfer logic is not tied to HTTP handlers.
3. Add USB WebSocket transport as a second adapter that reuses the same pairing/transfer handlers.
4. Expand QR payload to advertise both LAN bootstrap targets and USB bootstrap hints (`opt` + suggested port).
5. Keep existing persistence (`mobile_devices`, `mobile_folders`, `mobile_backup_sessions`, `mobile_assets`) and event bus semantics unchanged.

## Current coupling that must be removed
- `MobilePairingService` currently owns too many concerns:
  - pairing domain validation and persistence
  - HTTP server lifecycle
  - HTTP route dispatch for both pairing and transfer
  - JSON decoding/encoding and error mapping
- `MobileTransferService` is domain-focused but called directly from HTTP path routing in `mobile_pairing_service.py`.
- Endpoint contracts are currently path-driven (`/api/mobile/pairing/claim`, `/api/mobile/transfer/*`), so adding USB would duplicate logic unless we split transport from domain.

## Target module layout (desktop side)
Create a transport package under `dt_image_search/mobile/transport/`:

- `contracts.py`
  - transport enums and typed request/response models
  - operation names (`pairing.claim`, `transfer.start`, `transfer.existence`, `transfer.asset`, `transfer.complete`)
  - context model (`transport`, `remote`, `request_id`, `received_at`)
- `router.py`
  - operation-to-handler registration and dispatch
  - shared error-to-response mapping
- `lan_http_adapter.py`
  - `ThreadingHTTPServer` lifecycle and path mapping
  - request decoding and response writing for current HTTP API
- `usb_ws_adapter.py`
  - USB tunnel + WebSocket session lifecycle
  - envelope decode/encode and request/response correlation
- `transport_manager.py`
  - starts/stops adapters
  - exposes active pairing bootstrap URL(s) for LAN and runtime USB state

Refactor existing modules to focus on domain:

- `mobile_pairing_service.py`
  - keep pairing domain state/session lifecycle
  - remove embedded HTTP route handler implementation
- `mobile_transfer_service.py`
  - keep transfer domain methods as transport-agnostic handlers
  - no direct dependency on HTTP request objects

## Canonical transport message contract (JSON)
Use one internal operation model for both LAN and USB:

### QR bootstrap payload update (LAN + USB in one QR)
- Bump QR schema from `v=1` to `v=2` for new desktop-generated QR payloads.
- Keep existing fields:
  - `ept`: LAN endpoint targets (`host:port`)
  - `sid`: pairing session id
  - `opt`: one-time bootstrap token (reused for pairing claim and USB handshake auth)
- Add USB bootstrap fields:
  - `usp`: suggested USB bootstrap port (desktop-generated, mobile starts WS server on this port)
- Port policy:
  - generate `usp` randomly per QR pairing attempt within a safe configured port range
  - regenerate `usp` when QR token/session is refreshed
- Migration rule:
  - iOS QR decoder accepts both `v=1` and `v=2` during transition.
  - desktop emits `v=2` once both sides are ready.

- Request envelope:
  - `schema`: `dtis.mobile-transport.v1`
  - `operation`: one of the 5 operations above
  - `request_id`: client-generated UUID
  - `body_schema`: `dtis.mobile-pairing.v1` or `dtis.mobile-transfer.v1`
  - `body`: operation payload
- Response envelope:
  - `schema`: `dtis.mobile-transport.v1`
  - `request_id`: echoes request id
  - `status_code`: protocol-level status (same semantics as current HTTP status mapping)
  - `body`: existing pairing/transfer response JSON

LAN compatibility mapping:

- `POST /api/mobile/pairing/claim` -> `pairing.claim`
- `POST /api/mobile/transfer/start` -> `transfer.start`
- `POST /api/mobile/transfer/existence` -> `transfer.existence`
- `POST /api/mobile/transfer/asset` -> `transfer.asset`
- `POST /api/mobile/transfer/complete` -> `transfer.complete`

USB asset upload detail:

- Keep `transfer.asset` semantics unchanged.
- For WebSocket, send metadata envelope first, then binary frames for asset bytes, and finish with a transport-level completion frame referencing the same `request_id`.
- Reuse `MobileTransferService.handle_asset_upload` write path so dedupe/signature logic remains single-source.
- USB discovery/bootstrap uses QR-distributed `usp` + `opt`:
  - mobile starts listening on `usp` after scanning QR
  - desktop USB adapter uses usbmuxd tunneling and probes connected device(s) for `usp`, then fallback ports in `usp +/- 20`
  - handshake auth header follows `SHA256(opt + rand)` as described in `specs/[dev]usb-tunnel.md`

## Phase-by-phase refactor steps
### Phase 0 - Lock baseline behavior (no behavior changes)
1. Capture current behavior contract from tests:
   - pairing acceptance/rejection/expiry/status codes
   - transfer start/existence/store/skip/complete responses
   - event bus event (`mobile_transfer_started`)
2. Record "must not change" payload fields (`transport`, `server_nonce`, `folder_path`, `local_relative_path`, etc.).
3. Add QR contract migration checklist:
   - iOS decoder supports both `v=1` and `v=2`
   - desktop can emit `v=2` with `usp`
   - `opt` semantics expanded from "pairing passcode only" to "shared bootstrap token"
4. Add a migration checklist in this file before implementation starts.

### Phase 1 - Introduce transport contracts and router
1. Add `contracts.py` with typed operation/context models and constants.
2. Add `router.py` with:
   - deterministic operation dispatch
   - strict schema checks
   - shared error envelope generation
3. Implement adapter-independent helper for JSON object parsing (current `_read_json_payload` behavior).
4. Extend pairing session models (`mobile_pairing_session.py`) to carry USB bootstrap fields required by QR generation.
5. Add a deterministic `usp` allocator that picks a random port within configured safe bounds for each QR pairing attempt.

### Phase 2 - Extract domain handlers from HTTP implementation
1. In `mobile_pairing_service.py`, expose pairing claim as a pure handler entry (`handle_pairing_request`) that accepts parsed payload + context.
2. In `mobile_transfer_service.py`, expose transfer handlers with a consistent signature used by router.
3. Remove any direct HTTP-path branching from domain classes.
4. Keep lock/session semantics in pairing domain exactly as today.

### Phase 3 - Rebuild LAN transport as an adapter
1. Move `_MobilePairingHTTPServer` and request-handler class out of `mobile_pairing_service.py` into `lan_http_adapter.py`.
2. LAN adapter responsibilities:
   - parse HTTP path -> operation
   - parse JSON body or asset metadata/body stream
   - invoke router and write JSON response
3. Keep endpoint discovery and formatting behavior used by QR generation (`discover_advertised_hosts`, endpoint URL list).
4. Preserve current HTTP status code and response body compatibility.

### Phase 4 - Add USB WebSocket adapter
1. Implement USB tunnel lifecycle in `usb_ws_adapter.py`:
   - connect/disconnect state machine
   - monitor USB devices and probe QR-distributed suggested port (`usp`) plus fallback range `usp +/- 20`
   - request receive loop
   - response send with `request_id` correlation
2. Add auth handshake using QR bootstrap token:
   - desktop sends auth header derived from `SHA256(opt + rand)`
   - mobile validates bootstrap token + signature before accepting operation messages
3. Route incoming USB operations through the same router used by LAN.
4. Ensure transfer progress events and DB updates are identical to LAN path.

### Phase 5 - Transport manager integration
1. Add `transport_manager.py` to own lifecycle of LAN + USB adapters.
2. Update `MobilePairingService` to depend on transport manager rather than creating HTTP server directly.
3. Keep `MobileFolderCoordinator` flow unchanged from UI perspective.
4. Ensure `shutdown()` cleanly stops both adapters and background threads.

### Phase 6 - Cross-platform contract alignment (desktop + iOS)
1. Keep existing pairing/transfer payload schemas unchanged.
2. Update desktop QR generation to include `v=2` + `usp` and expanded `opt` semantics.
3. Update iOS `PairingQRCodePayload` and decoder to parse/store USB bootstrap fields while preserving existing LAN endpoint parsing.
4. Add transport envelope support on iOS networking layer for USB path while preserving current LAN HTTP clients.
5. Continue writing `transport` field (`lan`/`usb`) in pairing response and trusted desktop records.
6. Preserve LAN fallback when USB is unavailable.
7. Prefer USB automatically when available and handshake succeeds.

### Phase 7 - Test plan for the refactor
1. Existing desktop tests must continue passing:
   - `tests/unit/test_mobile_pairing_service.py`
   - `tests/unit/test_mobile_transfer_service.py`
   - `tests/unit/test_mobile_folder_controller.py`
2. Add desktop unit tests for:
   - router operation dispatch and schema rejection
   - LAN adapter path->operation mapping and error mapping
   - USB adapter request/response correlation and handshake rejection paths
3. Add iOS tests for:
   - transport envelope decode/encode for USB
   - LAN fallback if USB connection fails

## Rollout strategy
1. Land Phase 1-3 first (LAN-only refactor parity).
2. Ship USB adapter behind a runtime flag (disabled by default in first merge).
3. Enable USB in staged testing after parity metrics are stable.

## Clarification status (locked)
- Reuse `opt` as the shared bootstrap token for pairing claim and USB auth.
- Generate `usp` randomly per QR pairing attempt within a safe range.
- Probe `usp` with fallback range `usp +/- 20`.
- Prefer USB automatically when available, with LAN fallback on USB unavailability/failure.
