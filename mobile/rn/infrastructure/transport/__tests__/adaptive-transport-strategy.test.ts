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

function mock_fetch_ok(payload: unknown): void {
  globalThis.fetch = jest.fn().mockResolvedValue({
    ok: true,
    json: jest.fn().mockResolvedValue(payload),
  }) as unknown as typeof fetch;
}

class FailingAoaBridge extends FakeAoaBridge {
  async sendRequest(): Promise<string> {
    throw new Error('AOA transport failure');
  }

  async beginStreamingRequest(): Promise<string> {
    throw new Error('AOA transport failure');
  }

  async finishStreamingRequest(): Promise<string> {
    throw new Error('AOA transport failure');
  }
}

test('prefers AOA when connected', async () => {
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const response = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBeGreaterThan(0);
});

test('falls back to LAN when AOA is not connected', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FakeAoaBridge();
  bridge.connected = false;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const response = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBe(0);
});

test('falls back to LAN when AOA fails and reuses the cooldown', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FailingAoaBridge();
  bridge.connected = true;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const first = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(first.backup_state).toBe('pairing_completed');

  const second = await adaptive.claim_pairing(CLAIM_REQUEST);
  expect(second.backup_state).toBe('pairing_completed');
  expect(globalThis.fetch).toHaveBeenCalledTimes(2);
});

test('get_pairing_state falls back to LAN when AOA is not connected', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const bridge = new FakeAoaBridge();
  bridge.connected = false;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const response = await adaptive.get_pairing_state({
    schema: 'dtis.mobile-pairing.v1',
    session_id: 's1',
    device_uuid: 'd1',
  });
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.sentRequests.length).toBe(0);
});

test('create_transfer_client prefers AOA when connected', () => {
  const bridge = new FakeAoaBridge();
  bridge.connected = true;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const client = adaptive.create_transfer_client({
    endpoint_base_url: 'http://localhost',
    session_id: 's1',
    device_uuid: 'd1',
    trust_key_b64: 'key',
  });
  expect(client).toBeInstanceOf(AoaTransferClient);
});

test('create_transfer_client uses LAN when AOA is not connected', () => {
  const bridge = new FakeAoaBridge();
  bridge.connected = false;
  const aoa = new AoaTransportStrategy(bridge, { sessionId: 's1', oneTimePasscode: '123456' });
  const lan = new LanTransportStrategy('http://localhost');
  const adaptive = new AdaptiveTransportStrategy(aoa, lan, () => bridge.connected);

  const client = adaptive.create_transfer_client({
    endpoint_base_url: 'http://localhost',
    session_id: 's1',
    device_uuid: 'd1',
    trust_key_b64: 'key',
  });
  expect(client).toBeInstanceOf(DefaultHttpTransferClient);
});
