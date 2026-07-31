import { NativeModules } from 'react-native';
import type { AoaBridge, AoaBridgeStateEvent } from '@/infrastructure/transport/aoa/aoa-bridge';
import { NativeAoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';

export class FakeAoaBridge implements AoaBridge {
  prepared = false;
  connected = false;
  sentRequests: string[] = [];
  listeners: Array<(event: AoaBridgeStateEvent) => void> = [];

  async prepareBootstrap(): Promise<void> {
    this.prepared = true;
  }

  async reset(): Promise<void> {
    this.prepared = false;
    this.connected = false;
  }

  isConnected(): boolean {
    return this.connected;
  }

  async sendRequest(envelopeJson: string): Promise<string> {
    this.sentRequests.push(envelopeJson);
    return JSON.stringify({
      schema: 'dtis.mobile-transport.v1',
      request_id: JSON.parse(envelopeJson).request_id,
      status_code: 200,
      body: { status: 'accepted' },
    });
  }

  async beginStreamingRequest(envelopeJson: string): Promise<string> {
    return JSON.parse(envelopeJson).request_id;
  }

  async sendBinaryChunk(): Promise<void> {}

  async finishStreamingRequest(request_id: string): Promise<string> {
    return JSON.stringify({
      schema: 'dtis.mobile-transport.v1',
      request_id,
      status_code: 200,
      body: { status: 'stored' },
    });
  }

  addStateListener(listener: (event: AoaBridgeStateEvent) => void): () => void {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }
}

function install_mock_native_module(): Record<string, jest.Mock> {
  const module = {
    prepareBootstrap: jest.fn().mockResolvedValue(undefined),
    reset: jest.fn().mockResolvedValue(undefined),
    isConnected: jest.fn().mockReturnValue(true),
    sendRequest: jest.fn().mockResolvedValue('{"ok":true}'),
    beginStreamingRequest: jest.fn().mockResolvedValue('req-1'),
    sendBinaryChunk: jest.fn().mockResolvedValue(undefined),
    finishStreamingRequest: jest.fn().mockResolvedValue('{"ok":true}'),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
  };
  (NativeModules as Record<string, unknown>).AoaTransportModule = module;
  return module;
}

test('NativeAoaBridge forwards prepareBootstrap/reset/isConnected', async () => {
  const module = install_mock_native_module();
  const bridge = new NativeAoaBridge();

  await bridge.prepareBootstrap('s1', '123456', 45000);
  expect(module.prepareBootstrap).toHaveBeenCalledWith('s1', '123456', 45000);

  await bridge.reset();
  expect(module.reset).toHaveBeenCalled();

  expect(bridge.isConnected()).toBe(true);
  expect(module.isConnected).toHaveBeenCalled();
});

test('NativeAoaBridge forwards request and streaming calls', async () => {
  const module = install_mock_native_module();
  const bridge = new NativeAoaBridge();

  await bridge.sendRequest('{"envelope":1}');
  expect(module.sendRequest).toHaveBeenCalledWith('{"envelope":1}');

  const request_id = await bridge.beginStreamingRequest('{"envelope":2}');
  expect(module.beginStreamingRequest).toHaveBeenCalledWith('{"envelope":2}');
  expect(request_id).toBe('req-1');

  const chunk = new Uint8Array([1, 2, 3]);
  await bridge.sendBinaryChunk(request_id, chunk);
  expect(module.sendBinaryChunk).toHaveBeenCalledWith('req-1', [1, 2, 3]);

  await bridge.finishStreamingRequest(request_id);
  expect(module.finishStreamingRequest).toHaveBeenCalledWith('req-1');
});

test('NativeAoaBridge subscribes and unsubscribes state events', () => {
  const module = install_mock_native_module();
  const bridge = new NativeAoaBridge();

  const listener = jest.fn();
  const remove = bridge.addStateListener(listener);
  expect(module.addListener).toHaveBeenCalledWith('AoaTransportStateChanged');

  remove();
  expect(module.removeListeners).toHaveBeenCalled();
});
