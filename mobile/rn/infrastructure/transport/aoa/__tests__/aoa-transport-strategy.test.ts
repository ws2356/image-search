import type { PairingClaimRequest } from '@/features/backup/protocols/pairing';
import { AoaTransportStrategy } from '@/infrastructure/transport/aoa/aoa-transport-strategy';
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import { FakeAoaBridge } from '@/infrastructure/transport/aoa/__tests__/aoa-bridge.test';
import { TransportKind } from '@/infrastructure/transport/transport-kind';

const QR_PAYLOAD = { sessionId: 's1', oneTimePasscode: '123456', suggestedUsbPort: 45000 };

const CLAIM_REQUEST: PairingClaimRequest = {
  schema: 'dtis.mobile-pairing.v1',
  sid: 's1',
  opt: '123456',
  platform: 'android',
  device_uuid: 'd1',
  device_name: 'test',
  client_nonce: 'n1',
};

test('AoaTransportStrategy exposes the USB transport kind', () => {
  const strategy = new AoaTransportStrategy(new FakeAoaBridge(), QR_PAYLOAD);
  expect(strategy.kind).toBe(TransportKind.Usb);
});

test('AoaTransportStrategy claims pairing and prepares bootstrap', async () => {
  const bridge = new FakeAoaBridge();
  const strategy = new AoaTransportStrategy(bridge, QR_PAYLOAD);
  const response = await strategy.claim_pairing(CLAIM_REQUEST);
  expect(response.backup_state).toBe('pairing_completed');
  expect(bridge.prepared).toBe(true);
});

test('AoaTransportStrategy sends the pairing claim envelope', async () => {
  const bridge = new FakeAoaBridge();
  const strategy = new AoaTransportStrategy(bridge, QR_PAYLOAD);
  await strategy.claim_pairing(CLAIM_REQUEST);
  const envelope = JSON.parse(bridge.sentRequests[0]);
  expect(envelope.operation).toBe('pairing.claim');
  expect(envelope.body.sid).toBe('s1');
  expect(envelope.body.opt).toBe('123456');
});

test('AoaTransportStrategy gets pairing state', async () => {
  const bridge = new FakeAoaBridge();
  const strategy = new AoaTransportStrategy(bridge, QR_PAYLOAD);
  const response = await strategy.get_pairing_state({
    schema: 'dtis.mobile-pairing.v1',
    session_id: 's1',
    device_uuid: 'd1',
  });
  expect(response.backup_state).toBe('pairing_completed');
  expect(JSON.parse(bridge.sentRequests[0]).operation).toBe('pairing.state');
});

test('AoaTransportStrategy exchanges capabilities over AOA', async () => {
  const bridge = new FakeAoaBridge();
  const strategy = new AoaTransportStrategy(bridge, QR_PAYLOAD);
  const response = await strategy.exchange_capabilities({
    endpoint_base_url: '',
    session_id: 's1',
    device_uuid: 'd1',
    trust_proof: 'proof',
    capabilities: { encryption: 1 },
  });
  expect(response.status).toBe('accepted');
  const envelope = JSON.parse(bridge.sentRequests[0]);
  expect(envelope.operation).toBe('capabilities.exchange');
  expect(envelope.body.capabilities).toEqual({ encryption: 1, aoa_transfer: 1 });
  expect(envelope.body.trust_proof).toBe('proof');
});

test('AoaTransportStrategy create_transfer_client returns an AOA client', () => {
  const bridge = new FakeAoaBridge();
  const strategy = new AoaTransportStrategy(bridge, QR_PAYLOAD);
  const client = strategy.create_transfer_client({
    endpoint_base_url: '',
    session_id: 's1',
    device_uuid: 'd1',
    trust_key_b64: 'key',
  });
  expect(client).toBeInstanceOf(AoaTransferClient);
});
