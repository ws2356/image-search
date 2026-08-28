import { PermissionScope } from '@/features/backup/preflight/enums';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { startTransfer, type StartTransferDeps } from '@/features/backup/use-cases/start-transfer';
import type { NormalizedTransferAsset, TransferAssetSource } from '@/features/backup/services/transfer-asset-source';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferResponse } from '@/features/backup/protocols/transfer';
import type { TransferRuntimeWiring } from '@/infrastructure/platform/transfer-runtime-wiring';
import { NoopAndroidTransferService } from '@/infrastructure/platform/android-transfer-service';
import { NoopIosBackgroundTransferPolicy } from '@/infrastructure/platform/ios-background-transfer-policy';
import { NoopAppAwakePolicy } from '@/infrastructure/system/app-awake-policy';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';
import { TransportKind } from '@/infrastructure/transport/transport-kind';

jest.mock('@react-native-async-storage/async-storage', () => ({
  __esModule: true,
  default: {
    getItem: jest.fn(),
    setItem: jest.fn(),
    removeItem: jest.fn(),
  },
}));

jest.mock('expo-media-library', () => ({
  MediaType: { IMAGE: 'image', VIDEO: 'video' },
  AssetField: { MEDIA_TYPE: 'mediaType', CREATION_TIME: 'creationTime' },
  Asset: class {
    id: string;
    constructor(id: string) {
      this.id = id;
    }
    async getInfo() {
      return { filename: 'x.jpg', mediaType: 'image', creationTime: 1000, modificationTime: 1000 };
    }
    async getUri() {
      return `file:///${this.id}`;
    }
    async delete() {}
  },
  Query: class {
    within() {
      return this;
    }
    orderBy() {
      return this;
    }
    limit() {
      return this;
    }
    async exe() {
      return [];
    }
  },
}));

jest.mock('expo-file-system', () => ({
  File: class {
    constructor() {}
    open() {
      return { readBytes: () => new Uint8Array(), close: () => {} };
    }
  },
  FileMode: { ReadOnly: 'readonly' },
}));

const EXISTENCE_MATCHED_ASSET = 'match-1';
const STORED_ASSET = 'store-1';
const SKIPPED_ASSET = 'skip-1';
const FAILED_ASSET = 'fail-1';

function makeAsset(asset_id: string): NormalizedTransferAsset {
  return {
    asset_id,
    metadata: {
      asset_id,
      sha1: 'sha1',
      file_size: 1024,
      filename: `${asset_id}.jpg`,
      media_type: 'photo',
      created_at: '2026-01-01T00:00:00.000Z',
      updated_at: '2026-01-01T00:00:00.000Z',
    },
    dedupe_signature: {
      content_sha1: 'sha1',
      file_size_bytes: 1024,
      created_at: '2026-01-01T00:00:00.000Z',
    },
  };
}

function makeTransferClient(delete_via_fake: boolean): TransferClient {
  return {
    start: jest.fn().mockResolvedValue({ status: 'accepted', message: 'ok' }),
    existence: jest.fn().mockResolvedValue({
      status: 'checked',
      message: 'ok',
      matches: [{ asset_id: EXISTENCE_MATCHED_ASSET, local_relative_path: 'match.jpg' }],
    }),
    asset: jest.fn(async (metadata: { asset_id: string }, request_id: string, stream_state: string) => {
      void request_id;
      if (stream_state !== 'complete') {
        return { status: 'accepted', message: 'ok' } as TransferResponse;
      }
      if (metadata.asset_id === FAILED_ASSET) {
        throw new Error('desktop rejected asset');
      }
      return {
        status: metadata.asset_id === SKIPPED_ASSET ? 'skipped' : 'stored',
        message: 'ok',
      } as TransferResponse;
    }),
    complete: jest.fn().mockResolvedValue({ status: 'completed', message: 'ok' }),
  };
}

function makeDeps(overrides: {
  asset_source?: TransferAssetSource;
  transfer_client?: TransferClient;
  media_library_gateway?: {
    enumerate_transfer_candidates: jest.Mock;
    open_asset_chunk_reader: jest.Mock;
    delete_assets: jest.Mock;
  };
} = {}): {
  deps: StartTransferDeps;
  delete_assets: jest.Mock;
} {
  const delete_assets = overrides.media_library_gateway?.delete_assets ?? jest.fn().mockResolvedValue(3);
  const transfer_client = overrides.transfer_client ?? makeTransferClient(false);
  const asset_source: TransferAssetSource =
    overrides.asset_source ??
    {
      enumerate_normalized: jest.fn().mockResolvedValue([
        makeAsset(EXISTENCE_MATCHED_ASSET),
        makeAsset(STORED_ASSET),
        makeAsset(SKIPPED_ASSET),
        makeAsset(FAILED_ASSET),
      ]),
      open_asset_chunk_reader: jest.fn().mockResolvedValue({
        read_chunk: (length: number) => new Uint8Array(Math.min(length, 1024)),
        close: () => {},
      }),
    };

  const transport_strategy: TransportStrategy = {
    kind: TransportKind.Lan,
    claim_pairing: jest.fn(),
    get_pairing_state: jest.fn(),
    exchange_capabilities: jest.fn().mockResolvedValue({
      status: 'accepted',
      message: 'ok',
      capabilities: {},
    }),
    create_transfer_client: jest.fn().mockReturnValue(transfer_client),
  };

  const trust_proof_signer: TrustProofSigner = {
    derive_trust_proof: jest.fn().mockResolvedValue('proof'),
  };

  const transfer_runtime_wiring: TransferRuntimeWiring = {
    platform_capabilities: { platform: 'unknown', supports_usb_transport: false, supports_background_transfer_policy: false },
    android_transfer_service: new NoopAndroidTransferService(),
    ios_background_transfer_policy: new NoopIosBackgroundTransferPolicy(),
    app_awake_policy: new NoopAppAwakePolicy(),
  };

  const deps: StartTransferDeps = {
    apply_command: jest.fn().mockResolvedValue(undefined) as unknown as StartTransferDeps['apply_command'],
    trust_proof_signer,
    transport_strategy,
    transfer_runtime_wiring,
    transfer_asset_source: asset_source,
    media_library_gateway: {
      enumerate_transfer_candidates: overrides.media_library_gateway?.enumerate_transfer_candidates ?? jest.fn(),
      open_asset_chunk_reader: overrides.media_library_gateway?.open_asset_chunk_reader ?? jest.fn(),
      delete_assets,
    },
  };
  return { deps, delete_assets };
}

function seedSession(removeAfterBackupEnabled: boolean): void {
  useBackupSessionStore.setState({
    session: {
      ...useBackupSessionStore.getState().session,
      pairingSession: {
        sessionId: 's1',
        desktopName: 'desktop',
        endpointBaseUrl: 'http://127.0.0.1:45000',
        pairingCompletedAt: '2026-01-01T00:00:00.000Z',
        trustKeyB64: 'key',
        strictSecurityEnabled: false,
        encryptionEnabled: false,
      },
      localDeviceIdentity: {
        deviceUuid: 'd1',
        deviceName: 'phone',
        platform: 'android',
        updatedAt: '2026-01-01T00:00:00.000Z',
      },
      permissionSummary: {
        mediaScope: PermissionScope.Full,
        batteryPercentage: null,
        isCharging: false,
        lowBatteryWarningNeeded: false,
        removeAfterBackupEnabled,
      },
    },
  });
}

beforeEach(() => {
  useBackupSessionStore.setState({
    session: {
      ...useBackupSessionStore.getState().session,
      pairingSession: null,
      localDeviceIdentity: null,
    },
  });
});

test('startTransfer deletes only transferred or existence-checked assets, never failed ones', async () => {
  seedSession(true);
  const { deps, delete_assets } = makeDeps();

  await startTransfer({ abort_controller: new AbortController() }, deps);

  expect(delete_assets).toHaveBeenCalledTimes(1);
  const deletedIds = delete_assets.mock.calls[0][0] as string[];
  expect(deletedIds.sort()).toEqual([EXISTENCE_MATCHED_ASSET, STORED_ASSET, SKIPPED_ASSET].sort());
  expect(deletedIds).not.toContain(FAILED_ASSET);
});

test('startTransfer skips deletion when no assets were transferred', async () => {
  seedSession(true);
  const { deps, delete_assets } = makeDeps({
    asset_source: {
      enumerate_normalized: jest.fn().mockResolvedValue([]),
      open_asset_chunk_reader: jest.fn(),
    },
  });

  await startTransfer({ abort_controller: new AbortController() }, deps);

  expect(delete_assets).not.toHaveBeenCalled();
});
