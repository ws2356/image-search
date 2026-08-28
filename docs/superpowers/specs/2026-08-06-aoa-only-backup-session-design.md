# Design: AOA-Only Backup Session Support

Date: 2026-08-06
Status: Approved

## Goal

Make an Android backup session work end-to-end when only the AOA (Android Open Accessory) USB transport is available — no WiFi. Today the QR claim (`pairing.claim`) is only reachable over WiFi/LAN HTTP in practice: in an AOA-only session the mobile claim fires before the AOA handshake completes, skips AOA, falls back to LAN, and fails. After this change, all PC/mobile interactions must run over whichever transport is actually working (AOA or LAN), with LAN tried first on the first call and the last working transport preferred for later calls.

Scope: **Android (AuBackup RN + app) and the PC (AuSearch desktop only).** No iOS changes (iOS uses its own USB WebSocket tunnel; AOA is Android-only). No Kotlin/native changes required.

## Background

The desktop AOA adapter (`dt_image_search/mobile/transport/usb_aoa_adapter.py`) already serves the full request surface over AOA. It shares the `MobileTransportRouter` with LAN, so `pairing.claim`, `pairing.state`, `capabilities.exchange`, `transfer.start/existence/asset/complete`, and `update.prompt` are all routable over AOA (`_session_loop` → `_dispatch_envelope_request` → `router.dispatch`). The desktop side is complete.

The failure is mobile-side timing:

1. The user scans the QR; `AoaTransportStrategy.prepare_bootstrap` → `AoaBridge.prepareBootstrap` resolves immediately (the native call is synchronous and does not block on the handshake).
2. The PC↔phone AOA handshake (probe → negotiate accessory mode → open stream → `transport.auth.challenge` → proof = `SHA256(opt + rand)`) takes roughly 1–3 s before either side reports `CONNECTED`.
3. `AdaptiveTransportStrategy.can_try_aoa()` samples `is_aoa_connected()` exactly once (`adaptive-transport-strategy.ts:81`). At claim time it is still `false`, so AOA is skipped, LAN is attempted, and in an AOA-only session the LAN fetch fails.

## Design decisions

| Topic | Decision |
| --- | --- |
| Primary fix | Rewrite `AdaptiveTransportStrategy` (TypeScript only) as sequential transport fallback with a per-attempt timeout and a remembered working transport. |
| First call | `claim_pairing` tries **LAN first**, then AOA. |
| Per-transport timeout | **3 s** (configurable). LAN attempts are bounded with an abort timer; the AOA attempt uses its budget to **wait for the connection handshake**, then sends and waits on the native response timeout. |
| Remembered transport | The last transport that succeeded is tried **first** for later calls (`get_pairing_state`, `exchange_capabilities`, `create_transfer_client`). Recorded into the pairing session for transfer-time use. |
| Desktop reporting | Report `transport: "usb"` for sessions claimed over AOA/USB (currently always `"lan"` for Android). |
| Token refresh | Reconfigure the AOA bootstrap when the QR token is refreshed for Android too (currently iOS-only), so the AOA auth challenge stays in sync with a refreshed OTP. |
| Native changes | None. |
| Out of scope | iOS, LAN-HTTP-only fixes, update-prompt behavior, "old desktop without `aoa_transfer`" handling. |

## Mobile (AuBackup RN) changes

### 1. `AdaptiveTransportStrategy` v2 — `infrastructure/transport/adaptive-transport-strategy.ts`

Replace the "prefer AOA when connected + cooldown" logic with sequential-with-timeout. The class keeps the same `TransportStrategy` interface and constructor shape (adding an optional options object).

```ts
interface AdaptiveTransportStrategyOptions {
  transport_timeout_ms?: number;   // default 3000
  initial_preferred_transport?: 'lan' | 'usb';
}

readonly last_working_transport: 'lan' | 'usb' | null;  // public getter
```

Behavior:

- `claim_pairing(request)` — **first call, order `[LAN, USB]`**.
  - LAN attempt: `Promise.race` with a `transport_timeout_ms` abort timer. Timeout/failure → try AOA.
  - USB attempt: poll `is_aoa_connected()` (every ~100 ms) for up to `transport_timeout_ms`; if it connects, invoke `aoa_strategy.claim_pairing(request)` and await the real response (native `sendRequest` keeps its own 10 s response timeout — do **not** short-timeout a request once connected, so a slow-but-accepted claim is not reported as failed). If the connection does not establish within the budget → this attempt fails.
  - On success, set `preferred_transport` to the winning kind.
- `get_pairing_state(request)` / `exchange_capabilities(input)` — order `[preferred, other]`; default `[LAN, USB]` when nothing is remembered yet.
- `create_transfer_client(context)` — synchronous: use `preferred_transport`; when none is recorded, prefer AOA if `is_aoa_connected()`, else LAN.
- Both transport attempts failing throws an error with the last failure (used by the pairing controller to fail pairing).

### 2. Pairing flow — `features/backup/hooks/use-pairing-screen-controller.ts`

- Keep the early `aoa_bridge.prepareBootstrap(...)` call (idempotent, starts the handshake in the background while LAN is tried).
- After a successful claim/poll, read `strategy.last_working_transport` and pass it into `complete_pairing`.
- `PairingSessionSummary` (`features/backup/pairing/models.ts`) gains `transport?: 'lan' | 'usb'`; `complete_pairing` stores it (fallback `'lan'`).

### 3. Transfer wiring

- Generalize `build_headless_transfer_transport_strategy` (`features/backup/runtime/headless-transfer-transport.ts`) into a shared `build_transfer_transport_strategy(pairing_session)` that constructs an `AdaptiveTransportStrategy` with `initial_preferred_transport: pairing_session.transport`. Use it in the headless transfer task and the JS transfer path (`use-transfer-screen-controller.ts`, replacing the app-global strategy for start/stop).
- `features/backup/use-cases/start-transfer.ts`: `build_snapshot` stops hardcoding `transport: TransferTransport.Lan`; pass the strategy's working transport (AOA → `TransferTransport.Usb`, LAN → `TransferTransport.Lan`).

## Desktop (AuSearch) changes — `mobile/mobile_pairing_service.py`

1. **Accurate transport reporting.**
   - `_dispatch_pairing_claim_operation`: map `request.context.transport` → `'usb'` (`AOA_USB`, `USB_WEBSOCKET`) or `'lan'` (`LAN_HTTP`), and pass `claimed_transport` into `handle_pairing_request(payload, claimed_transport=...)`.
   - `handle_pairing_request(..., claimed_transport=None)` threads it into `_complete_pairing_acceptance`.
   - `_complete_pairing_acceptance`: use `claimed_transport` for `selected_transport` when provided; otherwise fall back to `_resolve_pairing_transport(platform)`. The response `transport` field, the acceptance message ("...ready for USB transfer" vs "...ready for LAN transfer"), and telemetry attributes then reflect the actual transport for AOA sessions.
   - Direct test calls without `claimed_transport` keep the current behavior (LAN default for Android).
2. **Token refresh keeps AOA auth fresh.**
   - `refresh_token`: call `_configure_usb_bootstrap_for_token` for **both** platforms (currently gated to iOS). This reconfigures the AOA bootstrap (`configure_aoa_bootstrap` + `start_aoa`) with the refreshed `session_id`/OTP/port so a refreshed QR does not break the AOA auth challenge.

## Non-goals

- No Kotlin/native changes.
- No iOS changes.
- No changes to the wire protocol, framing, auth handshake, or encryption.
- No changes to desktop update-prompt / capability-fallback behavior.

## Testing

### Mobile TypeScript (jest)

- Extend `infrastructure/transport/__tests__/adaptive-transport-strategy.test.ts`:
  - First `claim_pairing` tries LAN first even when AOA is connected.
  - LAN times out → falls back to AOA (waits for `is_aoa_connected`, sends claim) → remembers USB.
  - `get_pairing_state` prefers the remembered transport.
  - USB connect-wait timeout + LAN failure → throws.
  - `create_transfer_client` selects AOA/LAN from the remembered transport.
  - Use short injected `transport_timeout_ms` (and fake timers where supported) to keep tests fast.
- Add a test for `build_transfer_transport_strategy` using a recorded `session.transport`.
- Update the snapshot transport assertion in `features/backup/use-cases/__tests__` if present.

### Desktop Python

- `tests/unit/test_mobile_pairing_service.py`:
  - `handle_pairing_request` with `claimed_transport='usb'` returns `transport: 'usb'` and the "ready for USB transfer" acceptance message.
  - `refresh_token` for Android triggers AOA bootstrap reconfiguration (`configure_aoa_calls`/`start_aoa_calls`).
- Register/keep the tests in `dt_image_search/scripts/run_tests.sh`.

### Manual

- macOS + real Android device:
  - AOA-only: no WiFi, USB connected → scan QR, claim, poll, capability exchange, transfer, complete over AOA.
  - LAN-only: no USB → claim/transfer over WiFi.
  - Both available → LAN preferred on the first call, working transport remembered for later calls.
  - Token refresh mid-pairing → re-scan refreshed QR and complete over AOA.

## Relevant files

- `mobile/rn/infrastructure/transport/adaptive-transport-strategy.ts` — rewritten.
- `mobile/rn/features/backup/pairing/models.ts` — `PairingSessionSummary.transport`.
- `mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts` — record transport.
- `mobile/rn/features/backup/runtime/headless-transfer-transport.ts` — shared strategy builder.
- `mobile/rn/features/backup/hooks/use-transfer-screen-controller.ts` — session-specific strategy.
- `mobile/rn/features/backup/use-cases/start-transfer.ts` — snapshot transport label.
- `dt_image_search/mobile/mobile_pairing_service.py` — transport reporting + token refresh.
- Tests listed under Testing.
