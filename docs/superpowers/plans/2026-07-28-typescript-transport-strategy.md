# TypeScript Transport Strategy + Adaptive Selection + DI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the native AOA bridge into the React Native backup flow through a `TransportStrategy` abstraction, an adaptive strategy that prefers AOA and falls back to LAN, and a DI composition root.

**Architecture:** Introduce a `TransferClient` interface so `TransferService` can run over either HTTP or AOA. `TransportStrategy` becomes the top-level pairing/capability-exchange abstraction with a `create_transfer_client` factory. `LanTransportStrategy` and `AoaTransportStrategy` implement it. `AdaptiveTransportStrategy` chooses the concrete transport per operation and reuses a short cooldown after fallback. `AppServicesProvider` owns the instances and injects them into pairing and transfer hooks.

**Tech Stack:** TypeScript, React Native, Zustand, Jest.

## Global Constraints

- Use absolute imports from the package root (e.g., `@/features/backup/...`).
- Use full TypeScript type hints for all public functions and component props.
- Do not read full media files into JS memory; stream via the native layer or chunk callbacks.
- Use `react-native-quick-crypto` for trust proofs and encryption.
- The AOA transport must reuse the `dtis.mobile-transport.v1` envelope schema and iOS-compatible auth semantics.
- No automated end-to-end tests; cover each new unit with Jest mocks.

---

## Task 1: Introduce `TransferClient` interface and refactor `TransferService`

**Files:**
- Create: `mobile/rn/features/backup/services/transfer-client.ts`
- Modify: `mobile/rn/features/backup/services/transfer-service.ts`
- Modify: `mobile/rn/infrastructure/transport/lan/http-transfer-client.ts`
- Test: `mobile/rn/features/backup/services/__tests__/transfer-service.test.ts`

**Interfaces:**
- Consumes: `TransferAssetMetadata`, `TransferAssetSignature`, `TransferResponse`, `TransferSessionRequest`, `TransferAssetExistenceRequest`, `TransferCompleteRequest`.
- Produces: `TransferClient` interface; `TransferService` depends on it.

- [ ] **Step 1: Create `transfer-client.ts`**

```typescript
import type {
  TransferAssetExistenceRequest,
  TransferAssetMetadata,
  TransferCompleteRequest,
  TransferResponse,
  TransferSessionRequest,
} from '@/features/backup/protocols/transfer';

export interface TransferClient {
  start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
  existence(
    request: Omit<TransferAssetExistenceRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse>;
  asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse>;
  complete(request: Omit<TransferCompleteRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
}
```

- [ ] **Step 2: Make `DefaultHttpTransferClient` implement `TransferClient`**

Add `implements TransferClient` to `DefaultHttpTransferClient` in `infrastructure/transport/lan/http-transfer-client.ts`.

```typescript
import type { TransferClient } from '@/features/backup/services/transfer-client';

export class DefaultHttpTransferClient implements HttpTransferClient, TransferClient {
  ...existing body remains unchanged...
}
```

- [ ] **Step 3: Refactor `TransferService` to accept `TransferClient`**

Change `TransferServiceDeps`:

```typescript
export interface TransferServiceDeps {
  transfer_client: TransferClient;
  trust_proof_signer: TrustProofSigner;
}
```

Update the constructor to accept a `TransferClient`:

```typescript
constructor(context: TransferServiceContext, deps?: Partial<TransferServiceDeps>) {
  this.context = context;
  this.deps = {
    transfer_client: deps?.transfer_client ?? this._build_default_http_client(),
    trust_proof_signer: deps?.trust_proof_signer ?? new DefaultTrustProofSigner(),
  };
}

private _build_default_http_client(): TransferClient {
  const payload_cipher = this.context.encryption_enabled
    ? new TransferPayloadCipher(this.context.trust_key_b64)
    : new NoopPayloadCipher();
  return new DefaultHttpTransferClient(this.context.endpoint_base_url, fetch, payload_cipher);
}
```

Remove direct `HttpTransferClient` import dependency where possible.

- [ ] **Step 4: Write a test that `TransferService` works with a fake `TransferClient`**

```typescript
import { TransferService } from '@/features/backup/services/transfer-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import { MOBILE_TRANSFER_SCHEMA } from '@/features/backup/protocols/transfer';

const fakeClient: TransferClient = {
  start: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'accepted', message: 'ok' }),
  existence: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'checked', message: 'ok', matches: [] }),
  asset: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'stored', message: 'ok' }),
  complete: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'completed', message: 'ok' }),
};

test('TransferService uses injected TransferClient', async () => {
  const service = new TransferService(
    { endpoint_base_url: 'http://localhost', session_id: 's1', device_uuid: 'd1', trust_key_b64: 'key' },
    { transfer_client: fakeClient, trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') } }
  );
  await service.start(10);
  expect(fakeClient.start).toHaveBeenCalled();
});
```

- [ ] **Step 5: Run tests and confirm they pass**

Run: `cd mobile/rn && npm test -- transfer-service.test.ts`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add mobile/rn/features/backup/services/transfer-client.ts \
        mobile/rn/features/backup/services/transfer-service.ts \
        mobile/rn/infrastructure/transport/lan/http-transfer-client.ts \
        mobile/rn/features/backup/services/__tests__/transfer-service.test.ts
git commit -m "[LLM: opencode-go/kimi-k2.7-code] refactor: TransferService depends on TransferClient interface"
```

---

## Task 2: Update `TransportStrategy` interface and create `LanTransportStrategy`

**Files:**
- Modify: `mobile/rn/infrastructure/transport/transport-strategy.ts`
- Create: `mobile/rn/infrastructure/transport/lan/lan-transport-strategy.ts`
- Delete: `mobile/rn/infrastructure/transport/usb/usb-transport-strategy.ts` (replaced by AOA strategy)
- Test: `mobile/rn/infrastructure/transport/lan/__tests__/lan-transport-strategy.test.ts`

**Interfaces:**
- Consumes: `PairingClaimRequest`, `PairingStateRequest`, `PairingResponse`, `CapabilityExchangeServiceInput`, `CapabilityExchangeResponse`, `TransferServiceContext`, `TransferClient`.
- Produces: `TransportStrategy` with `claim_pairing`, `get_pairing_state`, `exchange_capabilities`, `create_transfer_client`.

- [ ] **Step 1: Update `transport-strategy.ts`**

```typescript
import type {
  PairingClaimRequest,
  PairingResponse,
  PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import type { TransportKind } from '@/infrastructure/transport/transport-kind';

export interface TransportStrategy {
  readonly kind: TransportKind;
  claim_pairing(request: PairingClaimRequest): Promise<PairingResponse>;
  get_pairing_state(request: PairingStateRequest): Promise<PairingResponse>;
  exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse>;
  create_transfer_client(context: TransferServiceContext): TransferClient;
}
```

- [ ] **Step 2: Implement `LanTransportStrategy`**

```typescript
import {
  PAIRING_PROTOCOL_SCHEMA,
  type PairingClaimRequest,
  type PairingResponse,
  type PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';
import { DefaultHttpPairingBootstrapClient } from '@/infrastructure/transport/lan/http-pairing-bootstrap-client';
import { DefaultHttpPairingStateClient } from '@/infrastructure/transport/lan/http-pairing-state-client';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export class LanTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Lan;

  constructor(private readonly endpoint_base_url: string) {}

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    const client = new DefaultHttpPairingBootstrapClient(this.endpoint_base_url);
    return client.claim(request);
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    const client = new DefaultHttpPairingStateClient(this.endpoint_base_url);
    return client.state(request);
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    const service = new HttpCapabilityExchangeService(fetch);
    return service.exchange(input);
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    const payload_cipher = context.encryption_enabled
      ? new (require('@/infrastructure/crypto/payload-cipher').TransferPayloadCipher)(context.trust_key_b64)
      : new (require('@/infrastructure/crypto/payload-cipher').NoopPayloadCipher)();
    return new DefaultHttpTransferClient(context.endpoint_base_url, fetch, payload_cipher);
  }
}
```

- [ ] **Step 3: Write tests for `LanTransportStrategy`**

```typescript
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';

test('LanTransportStrategy claim_pairing forwards to HTTP client', async () => {
  const strategy = new LanTransportStrategy('http://localhost');
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: jest.fn().mockResolvedValue({
      schema: 'dtis.mobile-pairing.v1',
      backup_state: 'pairing_completed',
      message: 'ok',
    }),
  });
  const response = await strategy.claim_pairing({
    schema: 'dtis.mobile-pairing.v1',
    sid: 's1',
    opt: '123456',
    platform: 'android',
    device_uuid: 'd1',
    device_name: 'test',
    client_nonce: 'n1',
  });
  expect(response.backup_state).toBe('pairing_completed');
});
```

- [ ] **Step 4: Run tests**

Run: `cd mobile/rn && npm test -- lan-transport-strategy.test.ts`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/rn/infrastructure/transport/transport-strategy.ts \
        mobile/rn/infrastructure/transport/lan/lan-transport-strategy.ts \
        mobile/rn/infrastructure/transport/lan/__tests__/lan-transport-strategy.test.ts \
        mobile/rn/infrastructure/transport/usb/usb-transport-strategy.ts
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: LAN transport strategy and updated interface"
```

---

## Task 3: Create `AoaBridge` typed wrapper

**Files:**
- Create: `mobile/rn/infrastructure/transport/aoa/aoa-bridge.ts`
- Test: `mobile/rn/infrastructure/transport/aoa/__tests__/aoa-bridge.test.ts`

**Interfaces:**
- Consumes: `NativeModules.AoaTransportModule`.
- Produces: `AoaBridge` with `prepareBootstrap`, `reset`, `isConnected`, `sendRequest`, `beginStreamingRequest`, `sendBinaryChunk`, `finishStreamingRequest`, `addStateListener`, `removeStateListener`.

- [ ] **Step 1: Create `aoa-bridge.ts`**

```typescript
import { NativeEventEmitter, NativeModules } from 'react-native';

export interface AoaBridgeStateEvent {
  state: 'IDLE' | 'PREPARING' | 'AUTHENTICATING' | 'CONNECTED' | 'DISCONNECTED' | 'FAILED';
  errorMessage?: string | null;
}

export interface AoaBridge {
  prepareBootstrap(session_id: string, one_time_passcode: string, suggested_port: number): Promise<void>;
  reset(): Promise<void>;
  isConnected(): boolean;
  sendRequest(envelopeJson: string): Promise<string>;
  beginStreamingRequest(envelopeJson: string): Promise<string>;
  sendBinaryChunk(request_id: string, chunk: Uint8Array): Promise<void>;
  finishStreamingRequest(request_id: string): Promise<string>;
  addStateListener(listener: (event: AoaBridgeStateEvent) => void): () => void;
}

const AOA_TRANSPORT_STATE_EVENT = 'AoaTransportStateChanged';

export class NativeAoaBridge implements AoaBridge {
  private readonly nativeModule = NativeModules.AoaTransportModule as {
    prepareBootstrap(sessionId: string, oneTimePasscode: string, suggestedPort: number): Promise<void>;
    reset(): Promise<void>;
    isConnected(): boolean;
    sendRequest(envelopeJson: string): Promise<string>;
    beginStreamingRequest(envelopeJson: string): Promise<string>;
    sendBinaryChunk(requestId: string, chunk: number[]): Promise<void>;
    finishStreamingRequest(requestId: string): Promise<string>;
  };
  private readonly eventEmitter = new NativeEventEmitter(NativeModules.AoaTransportModule);

  async prepareBootstrap(session_id: string, one_time_passcode: string, suggested_port: number): Promise<void> {
    return this.nativeModule.prepareBootstrap(session_id, one_time_passcode, suggested_port);
  }

  async reset(): Promise<void> {
    return this.nativeModule.reset();
  }

  isConnected(): boolean {
    return this.nativeModule.isConnected();
  }

  async sendRequest(envelopeJson: string): Promise<string> {
    return this.nativeModule.sendRequest(envelopeJson);
  }

  async beginStreamingRequest(envelopeJson: string): Promise<string> {
    return this.nativeModule.beginStreamingRequest(envelopeJson);
  }

  async sendBinaryChunk(request_id: string, chunk: Uint8Array): Promise<void> {
    const array = Array.from(chunk);
    return this.nativeModule.sendBinaryChunk(request_id, array);
  }

  async finishStreamingRequest(request_id: string): Promise<string> {
    return this.nativeModule.finishStreamingRequest(request_id);
  }

  addStateListener(listener: (event: AoaBridgeStateEvent) => void): () => void {
    const subscription = this.eventEmitter.addListener(AOA_TRANSPORT_STATE_EVENT, listener);
    return () => subscription.remove();
  }
}
```

- [ ] **Step 2: Write tests with a mock bridge**

```typescript
import type { AoaBridge, AoaBridgeStateEvent } from '@/infrastructure/transport/aoa/aoa-bridge';

export class FakeAoaBridge implements AoaBridge {
  prepared = false;
  connected = false;
  sentRequests: string[] = [];
  listeners: Array<(event: AoaBridgeStateEvent) => void> = [];

  async prepareBootstrap(): Promise<void> { this.prepared = true; }
  async reset(): Promise<void> { this.prepared = false; this.connected = false; }
  isConnected(): boolean { return this.connected; }
  async sendRequest(envelopeJson: string): Promise<string> {
    this.sentRequests.push(envelopeJson);
    return JSON.stringify({ schema: 'dtis.mobile-transport.v1', request_id: JSON.parse(envelopeJson).request_id, status_code: 200, body: { status: 'accepted' } });
  }
  async beginStreamingRequest(envelopeJson: string): Promise<string> { return JSON.parse(envelopeJson).request_id; }
  async sendBinaryChunk(): Promise<void> {}
  async finishStreamingRequest(request_id: string): Promise<string> { return JSON.stringify({ schema: 'dtis.mobile-transport.v1', request_id, status_code: 200, body: { status: 'stored' } }); }
  addStateListener(listener: (event: AoaBridgeStateEvent) => void): () => void {
    this.listeners.push(listener);
    return () => { this.listeners = this.listeners.filter((l) => l !== listener); };
  }
}
```

- [ ] **Step 3: Run tests**

Run: `cd mobile/rn && npm test -- aoa-bridge.test.ts`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add mobile/rn/infrastructure/transport/aoa/aoa-bridge.ts \
        mobile/rn/infrastructure/transport/aoa/__tests__/aoa-bridge.test.ts
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: typed AOA bridge wrapper"
```

---

## Task 4: Create `AoaTransferClient`

**Files:**
- Create: `mobile/rn/infrastructure/transport/aoa/aoa-transfer-client.ts`
- Test: `mobile/rn/infrastructure/transport/aoa/__tests__/aoa-transfer-client.test.ts`

**Interfaces:**
- Consumes: `AoaBridge`, `PayloadCipher`, `TrustProofSigner`, `TransferServiceContext`.
- Produces: `AoaTransferClient implements TransferClient`.

- [ ] **Step 1: Implement `AoaTransferClient`**

```typescript
import {
  MOBILE_TRANSFER_SCHEMA,
  type TransferAssetExistenceRequest,
  type TransferAssetMetadata,
  type TransferCompleteRequest,
  type TransferResponse,
  type TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { NoopPayloadCipher, TransferPayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import type { PayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { AoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';

const MOBILE_TRANSPORT_SCHEMA = 'dtis.mobile-transport.v1';

export interface AoaTransferClientDeps {
  payload_cipher: PayloadCipher;
  trust_proof_signer: TrustProofSigner;
}

export class AoaTransferClient implements TransferClient {
  private readonly bridge: AoaBridge;
  private readonly context: TransferServiceContext;
  private readonly deps: AoaTransferClientDeps;

  constructor(bridge: AoaBridge, context: TransferServiceContext, deps?: Partial<AoaTransferClientDeps>) {
    this.bridge = bridge;
    this.context = context;
    this.deps = {
      payload_cipher: deps?.payload_cipher ?? (context.encryption_enabled ? new TransferPayloadCipher(context.trust_key_b64) : new NoopPayloadCipher()),
      trust_proof_signer: deps?.trust_proof_signer ?? new DefaultTrustProofSigner(),
    };
  }

  async start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.start', body);
    return this.parse_response(response);
  }

  async existence(request: Omit<TransferAssetExistenceRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.existence', body);
    return this.parse_response(response);
  }

  async asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    if (stream_state === 'start') {
      const encrypted = await this.deps.payload_cipher.encrypt_json_payload(metadata);
      const body = { ...encrypted, stream_state, request_id, chunk_size: 256 * 1024 };
      const streaming_request_id = await this.bridge.beginStreamingRequest(JSON.stringify(this.envelope('transfer.asset', body, request_id)));
      return { schema: MOBILE_TRANSFER_SCHEMA, status: 'accepted', message: 'streaming started', request_id: streaming_request_id };
    }
    if (stream_state === 'chunk') {
      if (!content) throw new Error('AOA asset chunk requires content');
      const encrypted = await this.deps.payload_cipher.encrypt_binary_chunk(content);
      await this.bridge.sendBinaryChunk(request_id, encrypted);
      return { schema: MOBILE_TRANSFER_SCHEMA, status: 'accepted', message: 'chunk accepted', request_id };
    }
    const response = await this.bridge.finishStreamingRequest(request_id);
    return this.parse_response(response);
  }

  async complete(request: Omit<TransferCompleteRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.complete', body);
    return this.parse_response(response);
  }

  private async send_request(operation: string, body: object): Promise<string> {
    const request_id = this.generate_request_id();
    const envelope = this.envelope(operation, body, request_id);
    return this.bridge.sendRequest(JSON.stringify(envelope));
  }

  private envelope(operation: string, body: object, request_id: string) {
    return {
      schema: MOBILE_TRANSPORT_SCHEMA,
      operation,
      request_id,
      body_schema: MOBILE_TRANSFER_SCHEMA,
      body,
    };
  }

  private parse_response(raw: string): TransferResponse {
    const parsed = JSON.parse(raw);
    if (parsed.body && typeof parsed.body === 'object') {
      return parsed.body as TransferResponse;
    }
    return parsed as TransferResponse;
  }

  private generate_request_id(): string {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}
```

- [ ] **Step 2: Write tests**

```typescript
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import { FakeAoaBridge } from '@/infrastructure/transport/aoa/__tests__/aoa-bridge.test';

test('AoaTransferClient starts a transfer session', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, {
    endpoint_base_url: '',
    session_id: 's1',
    device_uuid: 'd1',
    trust_key_b64: 'key',
    encryption_enabled: false,
  });
  const response = await client.start({ session_id: 's1', device_uuid: 'd1', trust_proof: 'proof', total_assets: 5 });
  expect(response.status).toBe('accepted');
  expect(bridge.sentRequests.length).toBe(1);
});
```

- [ ] **Step 3: Run tests**

Run: `cd mobile/rn && npm test -- aoa-transfer-client.test.ts`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add mobile/rn/infrastructure/transport/aoa/aoa-transfer-client.ts \
        mobile/rn/infrastructure/transport/aoa/__tests__/aoa-transfer-client.test.ts
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: AOA transfer client"
```

---

## Task 5: Create `AoaTransportStrategy`

**Files:**
- Create: `mobile/rn/infrastructure/transport/aoa/aoa-transport-strategy.ts`
- Test: `mobile/rn/infrastructure/transport/aoa/__tests__/aoa-transport-strategy.test.ts`

**Interfaces:**
- Consumes: `AoaBridge`, `TransportStrategy`, `PairingClaimRequest`, `PairingStateRequest`, `CapabilityExchangeServiceInput`, `TransferServiceContext`, `TransferClient`.
- Produces: `AoaTransportStrategy implements TransportStrategy`.

- [ ] **Step 1: Implement `AoaTransportStrategy`**

```typescript
import {
  PAIRING_PROTOCOL_SCHEMA,
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
import { NoopPayloadCipher, TransferPayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import type { AoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

const MOBILE_TRANSPORT_SCHEMA = 'dtis.mobile-transport.v1';

export interface AoaTransportStrategyDeps {
  trust_proof_signer: TrustProofSigner;
}

export class AoaTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  constructor(
    private readonly bridge: AoaBridge,
    private readonly qr_payload: { sessionId: string; oneTimePasscode: string; suggestedUsbPort?: number },
    private readonly deps: AoaTransportStrategyDeps = { trust_proof_signer: new DefaultTrustProofSigner() }
  ) {}

  async prepare_bootstrap(): Promise<void> {
    const port = this.qr_payload.suggestedUsbPort ?? 45000;
    return this.bridge.prepareBootstrap(this.qr_payload.sessionId, this.qr_payload.oneTimePasscode, port);
  }

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    await this.prepare_bootstrap();
    const response = await this.bridge.sendRequest(JSON.stringify(this.envelope('pairing.claim', request)));
    return this.parse_pairing_response(response);
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    const response = await this.bridge.sendRequest(JSON.stringify(this.envelope('pairing.state', request)));
    return this.parse_pairing_response(response);
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    const trust_proof = await this.deps.trust_proof_signer.derive_trust_proof({
      purpose: 'capabilities.exchange',
      schema: 'dtis.mobile-capabilities.v1',
      session_id: input.session_id,
      device_uuid: input.device_uuid,
      trust_key_b64: input.trust_key_b64,
    });
    const body = {
      schema: 'dtis.mobile-capabilities.v1',
      session_id: input.session_id,
      device_uuid: input.device_uuid,
      trust_proof,
      capabilities: { ...input.capabilities, aoa_transfer: 1 },
    };
    const response = await this.bridge.sendRequest(JSON.stringify(this.envelope('capabilities.exchange', body)));
    return JSON.parse(response).body as CapabilityExchangeResponse;
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    return new AoaTransferClient(this.bridge, context);
  }

  private envelope(operation: string, body: object, request_id?: string) {
    return {
      schema: MOBILE_TRANSPORT_SCHEMA,
      operation,
      request_id: request_id ?? this.generate_request_id(),
      body_schema: PAIRING_PROTOCOL_SCHEMA,
      body,
    };
  }

  private parse_pairing_response(raw: string): PairingResponse {
    const parsed = JSON.parse(raw);
    return parsed.body as PairingResponse;
  }

  private generate_request_id(): string {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}
```

- [ ] **Step 2: Write tests**

```typescript
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { FakeAoaBridge } from '@/infrastructure/transport/aoa/__tests__/aoa-bridge.test';

test('AoaTransportStrategy claims pairing', async () => {
  const bridge = new FakeAoaBridge();
  const strategy = new AoaTransportStrategy(
    bridge,
    { sessionId: 's1', oneTimePasscode: '123456', suggestedUsbPort: 45000 },
    { trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') } }
  );
  const response = await strategy.claim_pairing({
    schema: 'dtis.mobile-pairing.v1',
    sid: 's1',
    opt: '123456',
    platform: 'android',
    device_uuid: 'd1',
    device_name: 'test',
    client_nonce: 'n1',
  });
  expect(response.status).not.toBe('rejected');
  expect(bridge.prepared).toBe(true);
});
```

- [ ] **Step 3: Run tests**

Run: `cd mobile/rn && npm test -- aoa-transport-strategy.test.ts`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add mobile/rn/infrastructure/transport/aoa/aoa-transport-strategy.ts \
        mobile/rn/infrastructure/transport/aoa/__tests__/aoa-transport-strategy.test.ts
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: AOA transport strategy"
```

---

## Task 6: Create `AdaptiveTransportStrategy`

**Files:**
- Create: `mobile/rn/infrastructure/transport/adaptive-transport-strategy.ts`
- Test: `mobile/rn/infrastructure/transport/__tests__/adaptive-transport-strategy.test.ts`

**Interfaces:**
- Consumes: `TransportStrategy` (LAN and AOA), `PairingClaimRequest`, `PairingStateRequest`, `CapabilityExchangeServiceInput`, `TransferServiceContext`, `TransferClient`.
- Produces: `AdaptiveTransportStrategy implements TransportStrategy`.

- [ ] **Step 1: Implement `AdaptiveTransportStrategy`**

```typescript
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

const AOA_RETRY_COOLDOWN_MS = 500;

export class AdaptiveTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  private aoa_unavailable_until = 0;
  private last_pairing_strategy: TransportStrategy | null = null;

  constructor(
    private readonly aoa_strategy: TransportStrategy,
    private readonly lan_strategy: TransportStrategy,
    private readonly is_aoa_connected: () => boolean
  ) {}

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    return this.execute_with_fallback(
      (s) => s.claim_pairing(request),
      (result) => { this.last_pairing_strategy = result.strategy; }
    );
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    return this.execute_with_fallback(
      (s) => s.get_pairing_state(request),
      () => {}
    );
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    return this.execute_with_fallback(
      (s) => s.exchange_capabilities(input),
      () => {}
    );
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    if (this.can_try_aoa()) {
      try {
        return this.aoa_strategy.create_transfer_client(context);
      } catch {
        this.mark_aoa_unavailable();
      }
    }
    return this.lan_strategy.create_transfer_client(context);
  }

  private async execute_with_fallback<T>(
    operation: (strategy: TransportStrategy) => Promise<T>,
    on_success: (result: { strategy: TransportStrategy; value: T }) => void
  ): Promise<T> {
    const try_aoa = this.can_try_aoa();
    if (try_aoa) {
      try {
        const value = await operation(this.aoa_strategy);
        on_success({ strategy: this.aoa_strategy, value });
        return value;
      } catch (error) {
        this.mark_aoa_unavailable();
      }
    }
    const value = await operation(this.lan_strategy);
    on_success({ strategy: this.lan_strategy, value });
    return value;
  }

  private can_try_aoa(): boolean {
    return this.is_aoa_connected() && Date.now() >= this.aoa_unavailable_until;
  }

  private mark_aoa_unavailable(): void {
    this.aoa_unavailable_until = Date.now() + AOA_RETRY_COOLDOWN_MS;
  }
}
```

- [ ] **Step 2: Write tests**

```typescript
import { AdaptiveTransportStrategy } from '@/infrastructure/transport/adaptive-transport-strategy';
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { FakeAoaBridge } from '@/infrastructure/transport/aoa/__tests__/aoa-bridge.test';

test('prefers AOA when connected', async () => {
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const response = await adaptive.claim_pairing({
    schema: 'dtis.mobile-pairing.v1',
    sid: 's1',
    opt: '123456',
    platform: 'android',
    device_uuid: 'd1',
    device_name: 'test',
    client_nonce: 'n1',
  });
  expect(response.status).not.toBe('rejected');
  expect(bridge.sentRequests.length).toBeGreaterThan(0);
});
```

- [ ] **Step 3: Run tests**

Run: `cd mobile/rn && npm test -- adaptive-transport-strategy.test.ts`
Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add mobile/rn/infrastructure/transport/adaptive-transport-strategy.ts \
        mobile/rn/infrastructure/transport/__tests__/adaptive-transport-strategy.test.ts
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: adaptive USB/LAN transport strategy"
```

---

## Task 7: Update `PairingService` and pairing hook

**Files:**
- Modify: `mobile/rn/features/backup/services/pairing-service.ts`
- Modify: `mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts`
- Modify: `mobile/rn/infrastructure/di/app-services-provider.tsx`

**Interfaces:**
- Consumes: `TransportStrategy`.
- Produces: `PairingService` uses a `TransportStrategy` instead of HTTP clients.

- [ ] **Step 1: Update `PairingService`**

```typescript
import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import type { PairingResponse } from '@/features/backup/protocols/pairing';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export interface PairingServiceDeps {
  transport_strategy: TransportStrategy;
}

export class PairingService {
  private readonly deps: PairingServiceDeps;

  constructor(deps: PairingServiceDeps) {
    this.deps = deps;
  }

  async claim_pairing(
    payload: PairingQRCodePayload,
    identity: PairingDeviceIdentity,
    capabilities: Record<string, 0 | 1> = {}
  ): Promise<PairingResponse> {
    return this.deps.transport_strategy.claim_pairing({
      schema: 'dtis.mobile-pairing.v1',
      sid: payload.sessionId,
      opt: payload.oneTimePasscode,
      platform: identity.platform,
      device_uuid: identity.deviceUuid,
      device_name: identity.deviceName,
      client_nonce: default_client_nonce(),
      capabilities,
    });
  }

  async get_pairing_state(session_id: string, device_uuid: string): Promise<PairingResponse> {
    return this.deps.transport_strategy.get_pairing_state({
      schema: 'dtis.mobile-pairing.v1',
      session_id,
      device_uuid,
    });
  }
}
```

- [ ] **Step 2: Update `AppServicesProvider`**

```typescript
import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { AdaptiveTransportStrategy } from '@/infrastructure/transport/adaptive-transport-strategy';
import { NativeAoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';

export interface AppServices {
  runtimeMode: AppRuntimeMode;
  aoa_bridge: NativeAoaBridge;
  transport_strategy: AdaptiveTransportStrategy;
}

function createAppServices(): AppServices {
  const aoa_bridge = new NativeAoaBridge();
  return {
    runtimeMode: 'native-capable',
    aoa_bridge,
    transport_strategy: new AdaptiveTransportStrategy(
      new AoaTransportStrategy(aoa_bridge, { sessionId: '', oneTimePasscode: '' }),
      new LanTransportStrategy(''),
      () => aoa_bridge.isConnected()
    ),
  };
}

export function createAoaTransportStrategyForQr(aoa_bridge: NativeAoaBridge, payload: PairingQRCodePayload): AoaTransportStrategy {
  return new AoaTransportStrategy(aoa_bridge, {
    sessionId: payload.sessionId,
    oneTimePasscode: payload.oneTimePasscode,
    suggestedUsbPort: payload.suggestedUsbPort,
  });
}
```

Note: the adaptive strategy needs to be recreated after QR scan with the concrete AOA strategy. Add a method on `AdaptiveTransportStrategy` to update the AOA strategy, or recreate it in the pairing hook.

- [ ] **Step 3: Update `use-pairing-screen-controller.ts`**

Replace `new PairingService(endpoint_base_url)` with:

```typescript
const { aoa_bridge, transport_strategy: base_strategy } = useAppServices();
const aoa_strategy = createAoaTransportStrategyForQr(aoa_bridge, payload);
const adaptive_strategy = new AdaptiveTransportStrategy(aoa_strategy, new LanTransportStrategy(endpoint_base_url), () => aoa_bridge.isConnected());
const pairing_service = new PairingService({ transport_strategy: adaptive_strategy });
```

Also set `claim_platform` to `'android'` instead of `'ios'`.

- [ ] **Step 4: Update `startTransfer` use-case**

In `features/backup/use-cases/start-transfer.ts`, inject `transport_strategy` into `StartTransferDeps`. Use `transport_strategy.exchange_capabilities(...)` instead of `HttpCapabilityExchangeService`. Use `transport_strategy.create_transfer_client(context)` instead of constructing `TransferService` with default HTTP client.

```typescript
export interface StartTransferDeps {
  apply_command: typeof apply_backup_command;
  trust_proof_signer: TrustProofSigner;
  transport_strategy: TransportStrategy;
  transfer_runtime_wiring: TransferRuntimeWiring;
  transfer_asset_source: TransferAssetSource;
}
```

Replace:

```typescript
const exchange = await deps.capability_exchange_service.exchange({...});
```

with:

```typescript
const exchange = await deps.transport_strategy.exchange_capabilities({
  endpoint_base_url,
  session_id,
  device_uuid,
  trust_proof,
  capabilities: { [TRANSFER_ENCRYPTION_CAPABILITY]: 1 },
});
```

Replace `TransferService` construction with:

```typescript
const transfer_client = deps.transport_strategy.create_transfer_client({
  endpoint_base_url,
  session_id,
  device_uuid,
  trust_key_b64,
  encryption_enabled: supports_transfer_encryption,
});
const transfer_service = new TransferService({
  endpoint_base_url,
  session_id,
  device_uuid,
  trust_key_b64,
  encryption_enabled: supports_transfer_encryption,
}, { transfer_client, trust_proof_signer: deps.trust_proof_signer });
```

- [ ] **Step 5: Update `use-transfer-screen-controller.ts`**

Pass the transport strategy from `useAppServices` into `startTransfer` deps.

- [ ] **Step 6: Commit**

```bash
git add mobile/rn/features/backup/services/pairing-service.ts \
        mobile/rn/features/backup/hooks/use-pairing-screen-controller.ts \
        mobile/rn/features/backup/use-cases/start-transfer.ts \
        mobile/rn/features/backup/hooks/use-transfer-screen-controller.ts \
        mobile/rn/infrastructure/di/app-services-provider.tsx
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: wire adaptive transport strategy into pairing and transfer"
```

---

## Task 8: Self-review

- [ ] Confirm `TransportStrategy` no longer contains the old `start_transfer`, `check_transfer_existence`, `upload_transfer_asset`, `complete_transfer` methods.
- [ ] Confirm every public function has type hints.
- [ ] Confirm `opt` is not stored in React state or JS logs.
- [ ] Search for `TODO`, `TBD`, or `implement later` in new files.
- [ ] Confirm Jest can run the new tests: `cd mobile/rn && npm test`.
- [ ] Confirm TypeScript compiles: `cd mobile/rn && npx tsc --noEmit`.

If gaps are found, fix them before marking the plan complete.
