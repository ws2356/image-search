import type {
  PairingClaimRequest,
  PairingStateRequest,
} from '@/features/backup/protocols/pairing';
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

const STATE_REQUEST: PairingStateRequest = {
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
    { transport_timeout_ms: 30, aoa_connect_timeout_ms: 30 }
  );

  await expect(adaptive.claim_pairing(CLAIM_REQUEST)).rejects.toThrow();
});

test('AOA connect-wait uses its own budget independent of the LAN timeout', async () => {
  mock_fetch_hanging();
  const bridge = new FakeAoaBridge();
  let connected = false;
  setTimeout(() => {
    connected = true;
  }, 60);
  const adaptive = new AdaptiveTransportStrategy(
    new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' }),
    new LanTransportStrategy('http://localhost'),
    () => connected,
    { transport_timeout_ms: 20, aoa_connect_timeout_ms: 200 }
  );

  const response = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBeGreaterThan(0);
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
  mock_fetch_hanging();
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
