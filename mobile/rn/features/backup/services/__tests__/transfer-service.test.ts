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

test('TransferService upload_asset_chunked drives asset stream states', async () => {
  const client: TransferClient = {
    start: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'accepted', message: 'ok' }),
    existence: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'checked', message: 'ok', matches: [] }),
    asset: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'stored', message: 'ok' }),
    complete: jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'completed', message: 'ok' }),
  };
  const service = new TransferService(
    { endpoint_base_url: 'http://localhost', session_id: 's1', device_uuid: 'd1', trust_key_b64: 'key' },
    { transfer_client: client, trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') } }
  );

  await service.upload_asset_chunked(
    { asset_id: 'a1', filename: 'photo.jpg' },
    async (_offset, length) => new Uint8Array(length),
    3,
    2
  );

  expect(client.asset).toHaveBeenCalledTimes(4);
  const states = (client.asset as jest.Mock).mock.calls.map((call) => call[2]);
  expect(states).toEqual(['start', 'chunk', 'chunk', 'complete']);
});

test('TransferService complete forwards counts and proof', async () => {
  const complete = jest.fn().mockResolvedValue({ schema: MOBILE_TRANSFER_SCHEMA, status: 'completed', message: 'ok' });
  const service = new TransferService(
    { endpoint_base_url: 'http://localhost', session_id: 's1', device_uuid: 'd1', trust_key_b64: 'key' },
    {
      transfer_client: { ...fakeClient, complete },
      trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') },
    }
  );

  await service.complete(4, 1);

  expect(complete).toHaveBeenCalledWith(
    expect.objectContaining({ transferred_count: 4, failed_count: 1, trust_proof: 'proof' }),
    undefined
  );
});

test('TransferService delegates connection-error detection to the client', () => {
  const is_connection_error = jest.fn().mockReturnValue(true);
  const service = new TransferService(
    { endpoint_base_url: 'http://localhost', session_id: 's1', device_uuid: 'd1', trust_key_b64: 'key' },
    {
      transfer_client: { ...fakeClient, is_connection_error },
      trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') },
    }
  );

  const error = new Error('AOA connection lost');
  expect(service.is_connection_error(error)).toBe(true);
  expect(is_connection_error).toHaveBeenCalledWith(error);
});

test('TransferService reports false for connection errors when the client has no resync concept', () => {
  const service = new TransferService(
    { endpoint_base_url: 'http://localhost', session_id: 's1', device_uuid: 'd1', trust_key_b64: 'key' },
    {
      transfer_client: fakeClient,
      trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') },
    }
  );

  expect(service.is_connection_error(new Error('AOA connection lost'))).toBe(false);
});

test('TransferService delegates wait_for_reconnection to the client', async () => {
  const wait_for_reconnection = jest.fn().mockResolvedValue(true);
  const service = new TransferService(
    { endpoint_base_url: 'http://localhost', session_id: 's1', device_uuid: 'd1', trust_key_b64: 'key' },
    {
      transfer_client: { ...fakeClient, wait_for_reconnection },
      trust_proof_signer: { derive_trust_proof: jest.fn().mockResolvedValue('proof') },
    }
  );

  await expect(service.wait_for_reconnection(5000)).resolves.toBe(true);
  expect(wait_for_reconnection).toHaveBeenCalledWith(5000);
});
