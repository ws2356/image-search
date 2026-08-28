# AOA-Only Backup Session Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an Android backup session work end-to-end over AOA USB when WiFi is unavailable, by making the mobile transport layer try LAN first, fall back to AOA (waiting for the AOA handshake), and remember the last working transport.

**Architecture:** Rewrite `AdaptiveTransportStrategy` (TypeScript) as sequential transport fallback with a per-attempt timeout and a remembered working transport. Record the working transport in the pairing session so transfer-time strategy builders prefer it. On the desktop, report the actual transport for AOA claims and keep the AOA bootstrap in sync on QR token refresh. No native/Kotlin changes.

**Tech Stack:** TypeScript/React Native (jest, tsc), Python 3.10 (unittest), `MobileTransportRouter` on the desktop.

**Spec:** `docs/superpowers/specs/2026-08-06-aoa-only-backup-session-design.md`

## Global Constraints

- Python 3.10; use `pathlib.Path`; absolute imports from package root.
- No `print()`/`logging` — telemetry via `dt_image_search.telemetry.telemetry_client.log` (do not change logging behavior in this plan).
- TypeScript: strict types, `snake_case` functions/variables, `PascalCase` classes. No new npm packages.
- Commits must end with `[LLM: deepseek-v4-flash]`.
- Each task must keep the repo building and its own tests passing.

---
---

### Task 1: Rewrite `AdaptiveTransportStrategy` as sequential-with-timeout

Rewrite the mobile transport selector so the claim tries LAN first, falls back to AOA (waiting for the AOA connection within its budget), and remembers the last working transport for later calls.

**Files:**
- Modify: `mobile/rn/infrastructure/transport/adaptive-transport-strategy.ts`
- Test: `mobile/rn/infrastructure/transport/__tests__/adaptive-transport-strategy.test.ts`

**Interfaces:**
- Produces:
  - `export type PreferredTransport = 'lan' | 'usb';`
  - `export interface AdaptiveTransportStrategyOptions { transport_timeout_ms?: number; initial_preferred_transport?: PreferredTransport; }`
  - `AdaptiveTransportStrategy` keeps the existing constructor `(aoa_strategy, lan_strategy, is_aoa_connected, options?)` and adds `get last_working_transport(): PreferredTransport | null`.
  - `claim_pairing` order `[lan, usb]`; `get_pairing_state`/`exchange_capabilities` order `[preferred, other]`; `create_transfer_client` prefers `preferred_transport` else AOA-when-connected.
- Consumes: existing `TransportStrategy`, `AoaTransportStrategy`, `LanTransportStrategy`, `FakeAoaBridge` from `mobile/rn/infrastructure/transport/aoa/__tests__/aoa-bridge.test.ts`.

- [ ] **Step 1: Rewrite `adaptive-transport-strategy.ts`**

Replace the whole file with:

```ts
import {
  type PairingClaimRequest,
  type PairingResponse,
  type PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export type PreferredTransport = 'lan' | 'usb';

const DEFAULT_TRANSPORT_TIMEOUT_MS = 3000;
const AOA_CONNECT_POLL_INTERVAL_MS = 100;

export interface AdaptiveTransportStrategyOptions {
  transport_timeout_ms?: number;
  initial_preferred_transport?: PreferredTransport;
}

function sleep(duration_ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, duration_ms);
  });
}

export class AdaptiveTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  private preferred_transport: PreferredTransport | null;
  private readonly transport_timeout_ms: number;

  constructor(
    private readonly aoa_strategy: TransportStrategy,
    private readonly lan_strategy: TransportStrategy,
    private readonly is_aoa_connected: () => boolean,
    options: AdaptiveTransportStrategyOptions = {}
  ) {
    this.preferred_transport = options.initial_preferred_transport ?? null;
    this.transport_timeout_ms = options.transport_timeout_ms ?? DEFAULT_TRANSPORT_TIMEOUT_MS;
  }

  get last_working_transport(): PreferredTransport | null {
    return this.preferred_transport;
  }

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    return this.run_candidates(['lan', 'usb'], (strategy) => strategy.claim_pairing(request));
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    return this.run_candidates(this.ordered_candidates(), (strategy) => strategy.get_pairing_state(request));
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    return this.run_candidates(this.ordered_candidates(), (strategy) => strategy.exchange_capabilities(input));
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    const preferred = this.preferred_transport ?? (this.is_aoa_connected() ? 'usb' : 'lan');
    if (preferred === 'usb' && this.is_aoa_connected()) {
      return this.aoa_strategy.create_transfer_client(context);
    }
    return this.lan_strategy.create_transfer_client(context);
  }

  private ordered_candidates(): PreferredTransport[] {
    if (this.preferred_transport === 'usb') {
      return ['usb', 'lan'];
    }
    return ['lan', 'usb'];
  }

  private async run_candidates<T>(
    candidates: PreferredTransport[],
    operation: (strategy: TransportStrategy) => Promise<T>
  ): Promise<T> {
    let last_error: Error | null = null;
    for (const kind of candidates) {
      try {
        const value = await this.attempt(kind, operation);
        this.preferred_transport = kind;
        return value;
      } catch (error) {
        last_error = error instanceof Error ? error : new Error(String(error));
      }
    }
    throw last_error ?? new Error('Both transports failed.');
  }

  private async attempt<T>(
    kind: PreferredTransport,
    operation: (strategy: TransportStrategy) => Promise<T>
  ): Promise<T> {
    if (kind === 'usb') {
      await this.wait_for_aoa_connection(this.transport_timeout_ms);
      return operation(this.aoa_strategy);
    }
    return this.with_timeout(operation(this.lan_strategy), this.transport_timeout_ms);
  }

  private async wait_for_aoa_connection(timeout_ms: number): Promise<void> {
    const deadline = Date.now() + timeout_ms;
    while (true) {
      if (this.is_aoa_connected()) {
        return;
      }
      const remaining = deadline - Date.now();
      if (remaining <= 0) {
        throw new Error('AOA connection could not be established in time.');
      }
      await sleep(Math.min(AOA_CONNECT_POLL_INTERVAL_MS, remaining));
    }
  }

  private async with_timeout<T>(promise: Promise<T>, timeout_ms: number): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        promise,
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new Error(`Transport attempt timed out after ${timeout_ms}ms.`)),
            timeout_ms
          );
        }),
      ]);
    } finally {
      if (timer !== undefined) {
        clearTimeout(timer);
      }
    }
  }
}
```

- [ ] **Step 2: Rewrite the test file `adaptive-transport-strategy.test.ts`**

Replace the whole file with:

```ts
import type { PairingClaimRequest } from '@/features/backup/protocols/pairing';
import { AdaptiveTransportStrategy } from '@/infrastructure/transport/adaptive-transport-strategy';
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';
import { FakeAoaBridge } from '@/infrastructure/transport/aoa/__tests__/aoa-bridge.test';

const CLAIM_REQUEST: PairingClaimRequest = {
  schema: 'dtis.mobile-pairing.v1',
  sid: 's1',
  opt: '123456',
  platform: 'android',
  device_uuid: 'd1',
  device_name: 'test',
  client_nonce: 'n1',
};

const PAIRING_RESPONSE = {
  schema: 'dtis.mobile-pairing.v1',
  backup_state: 'pairing_completed',
  message: 'ok',
};

const STATE_REQUEST = {
  schema: 'dtis.mobile-pairing.v1',
  session_id: 's1',
  device_uuid: 'd1',
};

const TRANSFER_CONTEXT = {
  endpoint_base_url: 'http://localhost',
  session_id: 's1',
  device_uuid: 'd1',
  trust_key_b64: 'key',
};

function mock_fetch_ok(payload: unknown): void {
  globalThis.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: jest.fn().mockResolvedValue(payload),
  }) as unknown as typeof fetch;
}

function mock_fetch_hanging(): void {
  globalThis.fetch = jest.fn().mockReturnValue(new Promise(() => {})) as unknown as typeof fetch;
}

function make_adaptive(
  bridge: FakeAoaBridge,
  options?: ConstructorParameters<typeof AdaptiveTransportStrategy>[3]
): AdaptiveTransportStrategy {
  return new AdaptiveTransportStrategy(
    new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' }),
    new LanTransportStrategy('http://localhost'),
    () => bridge.connected,
    options
  );
}

test('claim_pairing tries LAN first even when AOA is connected', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge);

  const response = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(globalThis.fetch).toHaveBeenCalled();
  expect(bridge.sentRequests.length).toBe(0);
  expect(adaptive.last_working_transport).toBe('lan');
});

test('claim_pairing falls back to AOA when LAN times out and AOA connects', async () => {
  mock_fetch_hanging();
  const bridge = new FakeAoaBridge();
  let connected = false;
  setTimeout(() => {
    connected = true;
  }, 30);
  const adaptive = new AdaptiveTransportStrategy(
    new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' }),
    new LanTransportStrategy('http://localhost'),
    () => connected,
    { transport_timeout_ms: 50 }
  );

  const response = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBeGreaterThan(0);
  expect(adaptive.last_working_transport).toBe('usb');
});

test('get_pairing_state prefers the remembered LAN transport', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FakeAoaBridge();
  bridge.connected = false;
  const adaptive = make_adaptive(bridge);

  await adaptive.claim_pairing(CLAIM_REQUEST);
  (globalThis.fetch as jest.Mock).mockClear();
  const response = await adaptive.get_pairing_state(STATE_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(globalThis.fetch).toHaveBeenCalled();
  expect(bridge.sentRequests.length).toBe(0);
});

test('get_pairing_state prefers the remembered USB transport after an AOA claim', async () => {
  mock_fetch_hanging();
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge, { transport_timeout_ms: 30 });

  await adaptive.claim_pairing(CLAIM_REQUEST);
  (globalThis.fetch as jest.Mock).mockClear();
  const response = await adaptive.get_pairing_state(STATE_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBeGreaterThan(0);
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

test('claim_pairing throws when both transports fail', async () => {
  mock_fetch_hanging();
  const adaptive = new AdaptiveTransportStrategy(
    new AoaTransportStrategy(new FakeAoaBridge(), { sessionId: 's1', oneTimePasscode: '123456' }),
    new LanTransportStrategy('http://localhost'),
    () => false,
    { transport_timeout_ms: 30 }
  );

  await expect(adaptive.claim_pairing(CLAIM_REQUEST)).rejects.toThrow();
});

test('create_transfer_client uses remembered USB transport', async () => {
  mock_fetch_hanging();
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge, { transport_timeout_ms: 30 });

  await adaptive.claim_pairing(CLAIM_REQUEST);
  const client = adaptive.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(AoaTransferClient);
});

test('create_transfer_client uses remembered LAN transport', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge);

  await adaptive.claim_pairing(CLAIM_REQUEST);
  const client = adaptive.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(DefaultHttpTransferClient);
});

test('create_transfer_client prefers AOA when connected with no remembered transport', () => {
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge);

  const client = adaptive.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(AoaTransferClient);
});

test('initial_preferred_transport usb tries AOA first', async () => {
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge, { initial_preferred_transport: 'usb' });

  const response = await adaptive.get_pairing_state(STATE_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBeGreaterThan(0);
  expect(globalThis.fetch).not.toHaveBeenCalled();
});

test('initial_preferred_transport lan tries LAN first', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const adaptive = make_adaptive(bridge, { initial_preferred_transport: 'lan' });

  const response = await adaptive.get_pairing_state(STATE_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBe(0);
  expect(globalThis.fetch).toHaveBeenCalled();
});
```

- [ ] **Step 3: Run the tests to verify they pass**

Run: `cd mobile/rn && npm test -- --runInBand infrastructure/transport/__tests__/adaptive-transport-strategy.test.ts`
Expected: all tests PASS (each test finishes in well under a second; total under ~5s).

- [ ] **Step 4: Typecheck**

Run: `cd mobile/rn && npm run typecheck`
Expected: no type errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/ws2356/dev/device-connect
git add mobile/rn/infrastructure/transport/adaptive-transport-strategy.ts mobile/rn/infrastructure/transport/__tests__/adaptive-transport-strategy.test.ts
git commit -m "feat(rn): sequential transport fallback with remembered preference [LLM: deepseek-v4-flash]"
```

---
---

### Task 2: Record the working transport in the pairing session

Persist the transport that actually paired so later flows (transfer) prefer it.

**Files:**
- Modify: `mobile/rn/features/backup/pairing/models.ts`
- Modify: `mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts`

**Interfaces:**
- Consumes: `AdaptiveTransportStrategy.last_working_transport` (from Task 1).
- Produces: `PairingSessionSummary.transport?: 'lan' | 'usb'`; `complete_pairing` in the pairing controller accepts a 7th `transport: 'lan' | 'usb'` argument.

- [ ] **Step 1: Add `transport` to `PairingSessionSummary`**

In `mobile/rn/features/backup/pairing/models.ts`, add a field to the `PairingSessionSummary` interface (after `encryptionEnabled`):

```ts
export interface PairingSessionSummary {
  sessionId: string | null;
  desktopName: string | null;
  endpointBaseUrl: string | null;
  pairingCompletedAt: string | null;
  trustKeyB64: string | null;
  strictSecurityEnabled: boolean;
  encryptionEnabled: boolean;
  transport?: 'lan' | 'usb';
}
```

- [ ] **Step 2: Track the strategy and pass the transport in `use-pairing-screen-controller.ts`**

Edit `mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts`:

1. After the `let mismatch_started_at_ms: number | null = null;` line inside the effect, add:

```ts
    let adaptive_strategy: AdaptiveTransportStrategy | null = null;
```

2. Change the `complete_pairing` function to accept the transport and include it in the session. Two precise edits, keeping the rest of the function (including the `if (!cancelled) { navigate_without_exit_prompt(...) }` navigation block) untouched:
   - In the parameter list, after `strict_security_enabled: boolean,`, add `transport: 'lan' | 'usb'`:

```ts
    const complete_pairing = async (
      response_session_id: string | null | undefined,
      response_desktop_name: string | null | undefined,
      endpoint_base_url: string,
      fallback_session_id: string,
      trust_key_b64: string,
      strict_security_enabled: boolean,
      transport: 'lan' | 'usb'
    ) => {
```

   - In the `session:` object of the `pairingCompleted` command, after `encryptionEnabled: false,`, add `transport,`:

3. Replace the pairing service construction with a hoisted strategy:

```ts
      adaptive_strategy = new AdaptiveTransportStrategy(
        createAoaTransportStrategyForQr(aoa_bridge, payload),
        new LanTransportStrategy(endpoint_base_url),
        () => aoa_bridge.isConnected()
      );
      const pairing_service = new PairingService({
        transport_strategy: adaptive_strategy,
      });
```

4. In `handle_response`, pass the working transport to `complete_pairing`. Replace the `pairing_completed` block:

```ts
        if (response.backup_state === 'pairing_completed') {
          await complete_pairing(
            response.session_id,
            response.desktop_name,
            endpoint_base_url,
            session_id,
            resolved_trust_key_b64,
            payload.strictSecurityEnabled,
            adaptive_strategy?.last_working_transport ?? 'lan'
          );
          return true;
        }
```

- [ ] **Step 3: Typecheck**

Run: `cd mobile/rn && npm run typecheck`
Expected: no type errors.

- [ ] **Step 4: Commit**

```bash
cd /Users/ws2356/dev/device-connect
git add mobile/rn/features/backup/pairing/models.ts mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts
git commit -m "feat(rn): record pairing transport in the pairing session [LLM: deepseek-v4-flash]"
```

---
---

### Task 3: Wire the recorded transport into transfer-time strategy builders

Make the headless transfer task and the JS transfer path build an adaptive strategy seeded with the session's recorded transport, and stop hardcoding the LAN label in transfer snapshots.

**Files:**
- Modify: `mobile/rn/features/backup/runtime/headless-transfer-transport.ts`
- Modify: `mobile/rn/features/backup/runtime/android-headless-transfer-task.ts`
- Modify: `mobile/rn/features/backup/runtime/__tests__/android-headless-transfer-task.test.ts`
- Modify: `mobile/rn/features/backup/hooks/use-transfer-screen-controller.ts`
- Modify: `mobile/rn/features/backup/use-cases/start-transfer.ts`

**Interfaces:**
- Consumes: `PairingSessionSummary.transport` (Task 2), `AdaptiveTransportStrategyOptions.initial_preferred_transport` (Task 1).
- Produces: `build_transfer_transport_strategy(pairing_session: PairingSessionSummary): TransportStrategy` (renamed from `build_headless_transfer_transport_strategy`).

- [ ] **Step 1: Rename and seed the strategy builder**

Replace `mobile/rn/features/backup/runtime/headless-transfer-transport.ts` with:

```ts
import type { PairingSessionSummary } from '@/features/backup/pairing/models';
import { AdaptiveTransportStrategy } from '@/infrastructure/transport/adaptive-transport-strategy';
import { NativeAoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export function build_transfer_transport_strategy(
  pairing_session: PairingSessionSummary
): TransportStrategy {
  const aoa_bridge = new NativeAoaBridge();
  return new AdaptiveTransportStrategy(
    new AoaTransportStrategy(aoa_bridge, {
      sessionId: pairing_session.sessionId ?? '',
      oneTimePasscode: '',
    }),
    new LanTransportStrategy(pairing_session.endpointBaseUrl ?? ''),
    () => aoa_bridge.isConnected(),
    { initial_preferred_transport: pairing_session.transport }
  );
}
```

- [ ] **Step 2: Update the headless task caller**

In `mobile/rn/features/backup/runtime/android-headless-transfer-task.ts`, update the import:

```ts
import {
  build_transfer_transport_strategy,
} from '@/features/backup/runtime/headless-transfer-transport';
```

and the call site:

```ts
  const transport_strategy = build_transfer_transport_strategy(task_payload.pairingSession);
```

- [ ] **Step 3: Update and extend the headless strategy tests**

In `mobile/rn/features/backup/runtime/__tests__/android-headless-transfer-task.test.ts`, update the import to `build_transfer_transport_strategy` and the two call sites inside the existing tests. Then add:

```ts
test('headless transfer strategy prefers LAN when the session was paired over LAN', () => {
  install_mock_native_module(true);
  const strategy = build_transfer_transport_strategy({ ...PAIRING_SESSION, transport: 'lan' });
  const client = strategy.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(DefaultHttpTransferClient);
});

test('headless transfer strategy prefers AOA when the session was paired over USB', () => {
  install_mock_native_module(true);
  const strategy = build_transfer_transport_strategy({ ...PAIRING_SESSION, transport: 'usb' });
  const client = strategy.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(AoaTransferClient);
});
```

- [ ] **Step 4: Build a session-seeded strategy in the transfer screen controller**

In `mobile/rn/features/backup/hooks/use-transfer-screen-controller.ts`:

1. Add the import:

```ts
import { build_transfer_transport_strategy } from '@/features/backup/runtime/headless-transfer-transport';
```

2. Replace `const { transport_strategy } = useAppServices();` with:

```ts
  const { transport_strategy: default_transport_strategy } = useAppServices();
  const pairing_session = useBackupSessionStore((state) => state.session.pairingSession);
  const transport_strategy = useMemo(
    () => (pairing_session ? build_transfer_transport_strategy(pairing_session) : default_transport_strategy),
    [pairing_session, default_transport_strategy]
  );
```

(`useMemo` is already imported on the file's first line.)

- [ ] **Step 5: Stop hardcoding the LAN transport label in snapshots**

In `mobile/rn/features/backup/use-cases/start-transfer.ts`:

1. In the `build_snapshot` input type, add `transport: TransferTransport;`:

```ts
function build_snapshot(input: {
  stage: TransferPipelineStage;
  total_assets: number;
  matched_assets: number;
  transferred_assets: number;
  failed_assets: number;
  active_asset_id: string | null;
  bytes_uploaded: number;
  sha1_elapsed_ms: number;
  sha1_measured_assets: number;
  started_at_ms: number;
  transport: TransferTransport;
}): TransferProgressSnapshot {
```

2. In the returned snapshot object, replace `transport: TransferTransport.Lan,` with `transport: input.transport,`.

3. After the `const endpoint_base_url = pairing_session.endpointBaseUrl;` line, add:

```ts
  const snapshot_transport: TransferTransport =
    pairing_session.transport === 'usb' ? TransferTransport.Usb : TransferTransport.Lan;
```

4. Add `transport: snapshot_transport,` to every `build_snapshot({ ... })` call in the file. Each call's input object gains the `transport: snapshot_transport,` field. The first call (the initial `Enumerating` snapshot) becomes:

```ts
    await apply_command({
      type: 'transferSnapshotUpdated',
      snapshot: build_snapshot({
        stage: TransferPipelineStage.Enumerating,
        total_assets: 0,
        matched_assets: 0,
        transferred_assets: 0,
        failed_assets: 0,
        active_asset_id: null,
        bytes_uploaded: 0,
        sha1_elapsed_ms: 0,
        sha1_measured_assets: 0,
        started_at_ms,
        transport: snapshot_transport,
      }),
    });
```

Apply the same single-line addition to the remaining calls: the second `Enumerating` snapshot after `transfer_service.start`, the `publish_snapshot` closure body, the two calls in `upload_asset` (the `Transferring` progress publish and the success/skipped publish), the two calls in `process_existence_batch`, and the final `Completing` snapshot.

- [ ] **Step 6: Run the RN tests and typecheck**

Run: `cd mobile/rn && npm test -- --runInBand features/backup/runtime/__tests__/android-headless-transfer-task.test.ts`
Expected: all tests PASS (including the two new ones).

Run: `cd mobile/rn && npm run typecheck`
Expected: no type errors.

- [ ] **Step 7: Commit**

```bash
cd /Users/ws2356/dev/device-connect
git add mobile/rn/features/backup/runtime/headless-transfer-transport.ts mobile/rn/features/backup/runtime/android-headless-transfer-task.ts mobile/rn/features/backup/runtime/__tests__/android-headless-transfer-task.test.ts mobile/rn/features/backup/hooks/use-transfer-screen-controller.ts mobile/rn/features/backup/use-cases/start-transfer.ts
git commit -m "feat(rn): seed transfer strategy with recorded transport [LLM: deepseek-v4-flash]"
```

---
---

### Task 4: Desktop reports the actual transport for AOA claims

Make the desktop pairing acceptance reflect the transport the claim actually arrived over (AOA/USB vs LAN), including the response `transport` field, the acceptance message, and telemetry.

**Files:**
- Modify: `dt_image_search/mobile/mobile_pairing_service.py`
- Test: `tests/unit/test_mobile_pairing_service.py`

**Interfaces:**
- Produces:
  - Module-level `def _transport_kind_label(transport: MobileTransportKind) -> str:` returning `PAIRING_TRANSPORT_USB` for `AOA_USB`/`USB_WEBSOCKET`, else `PAIRING_TRANSPORT_LAN`.
  - `handle_pairing_request(self, request_payload, *, now=None, claimed_transport: str | None = None)`.
  - `_complete_pairing_acceptance(..., backup_again_decision: MobileBackupAgainDecision, claimed_transport: str | None = None)`.
- Consumes: existing `PAIRING_TRANSPORT_LAN`/`PAIRING_TRANSPORT_USB` constants and `MobileTransportKind` (already imported at `mobile_pairing_service.py:68`).

- [ ] **Step 1: Add the transport-label helper**

In `dt_image_search/mobile/mobile_pairing_service.py`, add this module-level function (place it next to `_resolve_pairing_transport`):

```python
def _transport_kind_label(transport: MobileTransportKind) -> str:
    if transport in (MobileTransportKind.AOA_USB, MobileTransportKind.USB_WEBSOCKET):
        return PAIRING_TRANSPORT_USB
    return PAIRING_TRANSPORT_LAN
```

- [ ] **Step 2: Thread `claimed_transport` into the claim dispatch**

In `mobile_pairing_service.py`, replace the body of `_dispatch_pairing_claim_operation` (currently calls `self.handle_pairing_request(request.payload)`) with:

```python
    def _dispatch_pairing_claim_operation(self, request: MobileTransportRequest) -> MobileTransportResponse:
        if not isinstance(request.payload, dict):
            return MobileTransportResponse(
                status_code=400,
                payload={
                    "schema": PAIRING_PROTOCOL_SCHEMA,
                    "backup_state": MobileBackupState.PENDING_PAIRING.value,
                    "message": "Desktop requires JSON object payloads for pairing requests.",
                },
            )
        status_code, response_payload = self.handle_pairing_request(
            request.payload,
            claimed_transport=_transport_kind_label(request.context.transport),
        )
        return MobileTransportResponse(status_code=status_code, payload=response_payload)
```

- [ ] **Step 3: Accept and use `claimed_transport` in `handle_pairing_request`**

Update the `handle_pairing_request` signature (add the keyword-only param):

```python
    def handle_pairing_request(
        self,
        request_payload: dict[str, object],
        *,
        now: datetime | None = None,
        claimed_transport: str | None = None,
    ) -> tuple[int, dict[str, object]]:
```

Update the `_complete_pairing_acceptance(...)` call inside `handle_pairing_request` to pass it:

```python
                return self._complete_pairing_acceptance(
                    session_id=active_session.session_id,
                    requested_platform=requested_platform,
                    token=token,
                    device_uuid=device_uuid,
                    device_name=device_name,
                    client_nonce=client_nonce,
                    current_time=current_time,
                    backup_again_context=backup_again_context,
                    backup_again_decision=MobileBackupAgainDecision.BACKUP_IN_NEW_FOLDER,
                    claimed_transport=claimed_transport,
                )
```

- [ ] **Step 4: Use `claimed_transport` in `_complete_pairing_acceptance`**

Update the `_complete_pairing_acceptance` signature to add `claimed_transport: str | None = None,` as the final keyword-only parameter, and replace the transport selection line:

```python
        selected_transport = claimed_transport or self._resolve_pairing_transport(requested_platform)
```

- [ ] **Step 5: Add the desktop test for an AOA claim**

In `tests/unit/test_mobile_pairing_service.py`:

1. Add `PAIRING_CLAIM_OPERATION` to the imports from `dt_image_search.mobile.transport.contracts` (it currently imports `PAIRING_STATE_OPERATION`):

```python
from dt_image_search.mobile.transport.contracts import (
    PAIRING_CLAIM_OPERATION,
    PAIRING_STATE_OPERATION,
    MobileTransportContext,
    MobileTransportKind,
)
```

2. Add this test method to the test class:

```python
    def test_pairing_claim_route_reports_usb_transport_for_aoa(self):
        now = datetime(2026, 4, 10, 6, 50, tzinfo=timezone.utc)
        session = self._pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        token = session.token_for(MobilePlatform.ANDROID)

        dispatch_response = self._pairing_service._transport_router.dispatch(
            operation=PAIRING_CLAIM_OPERATION,
            payload={
                "schema": "dtis.mobile-pairing.v1",
                "sid": session.session_id,
                "opt": token.one_time_passcode,
                "platform": "android",
                "device_uuid": "android-device-aoa-001",
                "device_name": "Pixel AOA",
                "client_nonce": "aoa-client-nonce-123",
            },
            context=MobileTransportContext(
                transport=MobileTransportKind.AOA_USB,
                operation=PAIRING_CLAIM_OPERATION,
                request_id="claim-aoa-001",
                remote_address="aoa://android-device-aoa-001",
            ),
        )

        self.assertEqual(dispatch_response.status_code, 200)
        self.assertEqual(dispatch_response.payload["transport"], "usb")
        self.assertIn("USB transfer", dispatch_response.payload["message"])
```

- [ ] **Step 6: Run the desktop pairing service tests**

Run: `python tests/unit/test_mobile_pairing_service.py`
Expected: all tests PASS (existing + the new one).

- [ ] **Step 7: Commit**

```bash
cd /Users/ws2356/dev/device-connect
git add dt_image_search/mobile/mobile_pairing_service.py tests/unit/test_mobile_pairing_service.py
git commit -m "feat(desktop): report actual transport for AOA pairing claims [LLM: deepseek-v4-flash]"
```

---
---

### Task 5: Desktop reconfigures the AOA bootstrap on token refresh

Keep the AOA auth challenge in sync with a refreshed QR token so Android AOA-only sessions survive a QR refresh.

**Files:**
- Modify: `dt_image_search/mobile/mobile_pairing_service.py`
- Test: `tests/unit/test_mobile_pairing_service.py`

**Interfaces:**
- Consumes: existing `refresh_token`, `_configure_usb_bootstrap_for_token`, `_StubTransportManager`.

- [ ] **Step 1: Always reconfigure the USB/AOA bootstrap on refresh**

In `mobile_pairing_service.py`, in `refresh_token`, replace the platform-guarded block:

```python
        if platform == MobilePlatform.IOS:
            self._configure_usb_bootstrap_for_token(
                session_id=session_id,
                token=refreshed_token,
            )
        return refreshed_token
```

with:

```python
        self._configure_usb_bootstrap_for_token(
            session_id=session_id,
            token=refreshed_token,
        )
        return refreshed_token
```

- [ ] **Step 2: Add the Android refresh test**

In `tests/unit/test_mobile_pairing_service.py`, add this test method:

```python
    def test_refresh_android_token_reconfigures_aoa_bootstrap(self):
        pairing_service = MobilePairingService(
            self._ctx,
            listen_host="127.0.0.1",
            desktop_name="Studio Mac",
        )
        self.addCleanup(pairing_service.shutdown)
        transport_manager = _StubTransportManager()
        pairing_service._transport_manager = transport_manager

        now = datetime(2026, 4, 10, 8, 30, tzinfo=timezone.utc)
        session = pairing_service.start_pairing_session(self._temp_dir.name, now=now)
        refreshed_android_token = pairing_service.refresh_token(
            MobilePlatform.ANDROID,
            now=now + timedelta(seconds=30),
        )

        self.assertEqual(len(transport_manager.configure_aoa_calls), 2)
        refreshed_config = transport_manager.configure_aoa_calls[1]
        self.assertEqual(refreshed_config.session_id, session.session_id)
        self.assertEqual(refreshed_config.one_time_passcode, refreshed_android_token.one_time_passcode)
        self.assertEqual(refreshed_config.suggested_port, refreshed_android_token.suggested_usb_port)
        self.assertEqual(transport_manager.start_aoa_calls, 2)
```

- [ ] **Step 3: Run the desktop pairing service tests**

Run: `python tests/unit/test_mobile_pairing_service.py`
Expected: all tests PASS (existing + the new one).

- [ ] **Step 4: Commit**

```bash
cd /Users/ws2356/dev/device-connect
git add dt_image_search/mobile/mobile_pairing_service.py tests/unit/test_mobile_pairing_service.py
git commit -m "fix(desktop): reconfigure AOA bootstrap on token refresh for Android [LLM: deepseek-v4-flash]"
```

---
---

### Task 6: Full verification

Confirm both sides build and their test suites pass together.

**Files:**
- No source changes.

- [ ] **Step 1: Run the RN jest suite**

Run: `cd mobile/rn && npm test -- --runInBand`
Expected: the full jest suite passes (including the updated `adaptive-transport-strategy` and `android-headless-transfer-task` tests).

- [ ] **Step 2: Run the RN typecheck**

Run: `cd mobile/rn && npm run typecheck`
Expected: no type errors.

- [ ] **Step 3: Run the desktop pairing-related unit tests**

Run: `python tests/unit/test_mobile_pairing_service.py && python tests/unit/test_mobile_transport_manager.py`
Expected: both files pass.

- [ ] **Step 4: Run the broader desktop unit suite for the touched modules**

Run: `bash dt_image_search/scripts/run_tests.sh`
Expected: the suite passes; `test_mobile_pairing_service.py` is already registered there. (If the suite is slow, at minimum confirm the two targeted files from Step 3 pass.)

- [ ] **Step 5: Manual smoke checklist (documented for the user, not automated)**

On macOS with a real Android device:
1. No WiFi, USB connected → scan QR → claim/poll/capability-exchange/transfer/complete all succeed over AOA.
2. No USB, WiFi on → claim/transfer succeed over LAN.
3. Both available → claim uses LAN first; the working transport is remembered for later calls.
4. Refresh the QR mid-pairing → re-scan → pairing completes over AOA.
