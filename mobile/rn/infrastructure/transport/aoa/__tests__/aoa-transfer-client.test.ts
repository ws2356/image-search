import { MOBILE_TRANSFER_SCHEMA } from '@/features/backup/protocols/transfer';
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import { FakeAoaBridge } from '@/infrastructure/transport/aoa/__tests__/aoa-bridge.test';

const context = {
  endpoint_base_url: '',
  session_id: 's1',
  device_uuid: 'd1',
  trust_key_b64: 'key',
  encryption_enabled: false,
};

test('AoaTransferClient starts a transfer session', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, context);
  const response = await client.start({
    session_id: 's1',
    device_uuid: 'd1',
    trust_proof: 'proof',
    total_assets: 5,
  });
  expect(response.status).toBe('accepted');
  expect(bridge.sentRequests.length).toBe(1);
});

test('AoaTransferClient checks asset existence', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, context);
  const response = await client.existence({
    session_id: 's1',
    device_uuid: 'd1',
    trust_proof: 'proof',
    assets: [{ asset_id: 'a1' }],
  });
  expect(response.status).toBe('accepted');
  expect(JSON.parse(bridge.sentRequests[0]).operation).toBe('transfer.existence');
});

test('AoaTransferClient completes a transfer session', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, context);
  const response = await client.complete({
    session_id: 's1',
    device_uuid: 'd1',
    trust_proof: 'proof',
    transferred_count: 4,
    failed_count: 1,
  });
  expect(response.status).toBe('accepted');
  expect(JSON.parse(bridge.sentRequests[0]).operation).toBe('transfer.complete');
});

test('AoaTransferClient streams asset chunks through the bridge', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, context);

  const started = await client.asset(
    {
      schema: MOBILE_TRANSFER_SCHEMA,
      session_id: 's1',
      device_uuid: 'd1',
      trust_proof: 'proof',
      asset_id: 'a1',
      filename: 'photo.jpg',
      file_size: 3,
    },
    'req-1',
    'start'
  );
  expect(started.status).toBe('accepted');
  expect(started.request_id).toBe('req-1'.padEnd(36, ' '));

  await client.asset({} as never, 'req-1', 'chunk', new Uint8Array([1, 2, 3]));
  expect(bridge.sentRequests.length).toBe(0);

  const completed = await client.asset({} as never, 'req-1', 'complete');
  expect(completed.status).toBe('stored');
});

test('AoaTransferClient normalizes long asset request ids to a 36-byte stream id', async () => {
  class RecordingAoaBridge extends FakeAoaBridge {
    binaryChunkRequestIds: string[] = [];
    finishRequestIds: string[] = [];

    async sendBinaryChunk(request_id?: string): Promise<void> {
      this.binaryChunkRequestIds.push(request_id ?? '');
    }

    async finishStreamingRequest(request_id: string): Promise<string> {
      this.finishRequestIds.push(request_id);
      return JSON.stringify({
        schema: 'dtis.mobile-transport.v1',
        request_id,
        status_code: 200,
        body: { status: 'stored' },
      });
    }
  }

  const bridge = new RecordingAoaBridge();
  const client = new AoaTransferClient(bridge, context);
  const long_asset_id = 'content://media/external/images/media/1120';

  const started = await client.asset(
    {
      schema: MOBILE_TRANSFER_SCHEMA,
      session_id: 's1',
      device_uuid: 'd1',
      trust_proof: 'proof',
      asset_id: long_asset_id,
      filename: 'photo.jpg',
      file_size: 3,
    },
    long_asset_id,
    'start'
  );
  expect(started.status).toBe('accepted');
  expect(started.request_id).toHaveLength(36);

  await client.asset({} as never, long_asset_id, 'chunk', new Uint8Array([1, 2, 3]));
  await client.asset({} as never, long_asset_id, 'complete');

  expect(bridge.binaryChunkRequestIds).toEqual([started.request_id]);
  expect(bridge.finishRequestIds).toEqual([started.request_id]);
});

test('AoaTransferClient rejects a chunk without content', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, context);
  await expect(client.asset({} as never, 'req-1', 'chunk')).rejects.toThrow('requires content');
});

test('AoaTransferClient throws an abort error when the signal is aborted without throwIfAborted', async () => {
  const bridge = new FakeAoaBridge();
  const client = new AoaTransferClient(bridge, context);
  const aborted_signal = { aborted: true } as AbortSignal;
  await expect(
    client.start(
      { session_id: 's1', device_uuid: 'd1', trust_proof: 'proof', total_assets: 5 },
      aborted_signal
    )
  ).rejects.toThrow('Transfer stopped by user.');
  expect(bridge.sentRequests.length).toBe(0);
});
