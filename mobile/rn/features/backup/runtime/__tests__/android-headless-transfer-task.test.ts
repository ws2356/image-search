import { NativeModules } from 'react-native';

import type { PairingSessionSummary } from '@/features/backup/pairing/models';
import {
  build_transfer_transport_strategy,
} from '@/features/backup/runtime/headless-transfer-transport';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';

const PAIRING_SESSION: PairingSessionSummary = {
  sessionId: 's1',
  desktopName: 'test desktop',
  endpointBaseUrl: 'http://127.0.0.1:45000',
  pairingCompletedAt: '2026-01-01T00:00:00.000Z',
  trustKeyB64: 'key',
  strictSecurityEnabled: false,
  encryptionEnabled: true,
};

const TRANSFER_CONTEXT: TransferServiceContext = {
  endpoint_base_url: 'http://127.0.0.1:45000',
  session_id: 's1',
  device_uuid: 'd1',
  trust_key_b64: 'key',
  encryption_enabled: true,
};

function install_mock_native_module(is_connected: boolean): Record<string, jest.Mock> {
  const module = {
    prepareBootstrap: jest.fn().mockResolvedValue(undefined),
    reset: jest.fn().mockResolvedValue(undefined),
    isConnected: jest.fn().mockReturnValue(is_connected),
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

test('headless transfer strategy prefers the AOA transfer client when USB is connected', () => {
  install_mock_native_module(true);
  const strategy = build_transfer_transport_strategy(PAIRING_SESSION);
  const client = strategy.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(AoaTransferClient);
});

test('headless transfer strategy falls back to the LAN transfer client when USB is not connected', () => {
  install_mock_native_module(false);
  const strategy = build_transfer_transport_strategy(PAIRING_SESSION);
  const client = strategy.create_transfer_client(TRANSFER_CONTEXT);
  expect(client).toBeInstanceOf(DefaultHttpTransferClient);
});

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
