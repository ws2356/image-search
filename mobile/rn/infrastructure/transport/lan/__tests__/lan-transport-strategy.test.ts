import { LanTransportStrategy } from '@/infrastructure/transport/lan/lan-transport-strategy';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';
import { TransportKind } from '@/infrastructure/transport/transport-kind';

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

test('LanTransportStrategy exposes the LAN transport kind', () => {
  const strategy = new LanTransportStrategy('http://localhost');
  expect(strategy.kind).toBe(TransportKind.Lan);
});

test('LanTransportStrategy claim_pairing forwards to HTTP client', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const strategy = new LanTransportStrategy('http://localhost');
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

test('LanTransportStrategy get_pairing_state forwards to HTTP client', async () => {
  mock_fetch_ok(PAIRING_RESPONSE);
  const strategy = new LanTransportStrategy('http://localhost');
  const response = await strategy.get_pairing_state({
    schema: 'dtis.mobile-pairing.v1',
    session_id: 's1',
    device_uuid: 'd1',
  });
  expect(response.backup_state).toBe('pairing_completed');
});

test('LanTransportStrategy create_transfer_client returns an HTTP client', () => {
  const strategy = new LanTransportStrategy('http://localhost');
  const client = strategy.create_transfer_client({
    endpoint_base_url: 'http://localhost',
    session_id: 's1',
    device_uuid: 'd1',
    trust_key_b64: 'key',
  });
  expect(client).toBeInstanceOf(DefaultHttpTransferClient);
});
