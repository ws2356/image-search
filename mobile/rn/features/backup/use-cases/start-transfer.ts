import QuickCrypto from 'react-native-quick-crypto';
import { assert_transfer_not_live_in_phase4 } from '@/features/backup/services/phase-scope';
import { TransferService } from '@/features/backup/services/transfer-service';
import type { CapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import {
  DefaultTransferAssetSource,
  type NormalizedTransferAsset,
  type TransferAssetSource,
} from '@/features/backup/services/transfer-asset-source';
import {
  TRANSFER_ENCRYPTION_CAPABILITY,
  TRANSFER_EXISTENCE_ASSET_VERSION_CAPABILITY,
} from '@/features/backup/protocols/capabilities';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { TransferFailureReason, TransferPipelineStage, TransferTransport } from '@/features/backup/transfer/enums';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import type { TransferAssetSignature } from '@/features/backup/protocols/transfer';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import {
  create_transfer_abort_error,
  is_transfer_abort_error,
} from '@/features/backup/transfer/transfer-abort';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import {
  begin_transfer_runtime_session,
  end_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';

export interface StartTransferDeps {
  apply_command: typeof apply_backup_command;
  trust_proof_signer: TrustProofSigner;
  capability_exchange_service: CapabilityExchangeService;
  transfer_runtime_wiring: TransferRuntimeWiring;
  transfer_asset_source: TransferAssetSource;
}

export interface StartTransferOptions {
  abort_controller: AbortController;
  should_abort?: () => boolean;
}

const TRANSFER_EXISTENCE_BATCH_SIZE = 15;
const TRANSFER_CONCURRENT_UPLOAD_LIMIT = 5;
const TRANSFER_CONCURRENT_SHA1_LIMIT = 3;
const CAPABILITY_EXCHANGE_MAX_ATTEMPTS = 3;
const CAPABILITY_EXCHANGE_RETRY_DELAY_MS = 500;

function delay(duration_ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, duration_ms);
  });
}

class AsyncQueue<T> {
  private readonly items: T[] = [];
  private readonly waiters: Array<(item: T | undefined) => void> = [];
  private closed = false;

  push(item: T): void {
    if (this.closed) {
      return;
    }
    const waiter = this.waiters.shift();
    if (waiter) {
      waiter(item);
      return;
    }
    this.items.push(item);
  }

  tryShift(): T | undefined {
    if (this.items.length === 0) {
      return undefined;
    }
    return this.items.shift();
  }

  async shift(): Promise<T | undefined> {
    const immediate = this.tryShift();
    if (immediate !== undefined) {
      return immediate;
    }
    if (this.closed) {
      return undefined;
    }
    return new Promise<T | undefined>((resolve) => {
      this.waiters.push(resolve);
    });
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    while (this.waiters.length > 0) {
      const waiter = this.waiters.shift();
      waiter?.(undefined);
    }
  }
}

function build_snapshot(input: {
  stage: TransferPipelineStage;
  total_assets: number;
  matched_assets: number;
  transferred_assets: number;
  failed_assets: number;
  active_asset_id: string | null;
  bytes_uploaded: number;
  sha1_elapsed_ms: number;
  sha1_measured_assets: number;
  started_at_ms: number;
}): TransferProgressSnapshot {
  const elapsed_seconds = Math.max(1, (Date.now() - input.started_at_ms) / 1000);
  const remaining_assets = Math.max(
   0,
   input.total_assets - input.transferred_assets - input.matched_assets - input.failed_assets
  );
  const bytes_per_second = input.bytes_uploaded > 0 ? input.bytes_uploaded / elapsed_seconds : null;
  const average_sha1_seconds_per_asset =
   input.sha1_measured_assets > 0 ? input.sha1_elapsed_ms / 1000 / input.sha1_measured_assets : 0;
  const estimated_sha1_seconds_remaining =
   remaining_assets > 0 ? Math.ceil(remaining_assets * average_sha1_seconds_per_asset) : 0;
  const estimated_transfer_seconds_remaining =
   bytes_per_second && bytes_per_second > 0 && input.transferred_assets > 0 && remaining_assets > 0
     ? Math.ceil((remaining_assets * (input.bytes_uploaded / input.transferred_assets)) / bytes_per_second)
     : 0;
  const estimated_seconds_remaining = estimated_sha1_seconds_remaining + estimated_transfer_seconds_remaining;
  return {
    pipelineStage: input.stage,
    transport: TransferTransport.Lan,
    counts: {
      totalAssets: input.total_assets,
      matchedAssets: input.matched_assets,
      transferredAssets: input.transferred_assets,
      failedAssets: input.failed_assets,
    },
    activeAssetId: input.active_asset_id,
    activeRequestId: input.active_asset_id ? `asset-${input.active_asset_id}` : null,
    bytesUploaded: input.bytes_uploaded,
    bytesPerSecond: bytes_per_second,
    estimatedSecondsRemaining: estimated_seconds_remaining,
    startedAt: new Date(input.started_at_ms).toISOString(),
    lastUpdatedAt: new Date().toISOString(),
  };
}

async function compute_asset_sha1(
  asset_id: string,
  transfer_asset_source: TransferAssetSource,
  throw_if_transfer_stopped?: () => void
): Promise<string> {
  const chunk_reader = await transfer_asset_source.open_asset_chunk_reader(asset_id, 0);
  const hasher = QuickCrypto.createHash('sha1');
  try {
    while (true) {
      throw_if_transfer_stopped?.();
      const chunk = chunk_reader.read_chunk(1024 * 1024);
      if (chunk.length === 0) {
        break;
      }
      hasher.update(chunk);
    }
  } finally {
    chunk_reader.close();
  }
  return hasher.digest('hex');
}

export async function startTransfer(
  options: StartTransferOptions,
  deps: StartTransferDeps = {
    apply_command: apply_backup_command,
    trust_proof_signer: new DefaultTrustProofSigner(),
    capability_exchange_service: new HttpCapabilityExchangeService(),
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
    transfer_asset_source: new DefaultTransferAssetSource(),
  }
): Promise<void> {
  assert_transfer_not_live_in_phase4('startTransfer');
  const session = useBackupSessionStore.getState().session;
  const pairing_session = session.pairingSession;
  if (!pairing_session?.sessionId || !pairing_session.endpointBaseUrl) {
    await deps.apply_command({
      type: 'transferResolved',
      result: {
        kind: 'failure',
        reason: TransferFailureReason.Unknown,
        error: {
          title: 'Transfer unavailable',
          message: 'Pairing session is missing. Pair a desktop first.',
        },
      },
    });
    return;
  }

  const device_uuid = session.localDeviceIdentity?.deviceUuid;
  const trust_key_b64 = pairing_session.trustKeyB64;
  if (!device_uuid || !trust_key_b64) {
    await deps.apply_command({
      type: 'transferResolved',
      result: {
        kind: 'failure',
        reason: TransferFailureReason.Unknown,
        error: {
          title: 'Transfer unavailable',
          message: 'Pairing data is incomplete. Pair this desktop again before starting transfer.',
        },
      },
    });
    return;
  }

  const session_id = pairing_session.sessionId;
  const endpoint_base_url = pairing_session.endpointBaseUrl;
  const strict_security_enabled = pairing_session.strictSecurityEnabled === true;
  const started_at_ms = Date.now();
  let runtime_started = false;
  let aborted_by_pipeline_error = false;
  const transfer_abort_signal = options.abort_controller.signal;
  const throw_if_transfer_stopped = () => {
    if (options.should_abort?.()) {
      options.abort_controller.abort();
    }
    if (transfer_abort_signal.aborted) {
      throw create_transfer_abort_error();
    }
  };

  try {
    await deps.apply_command({
      type: 'transferSnapshotUpdated',
      snapshot: build_snapshot({
        stage: TransferPipelineStage.Enumerating,
        total_assets: 0,
        matched_assets: 0,
        transferred_assets: 0,
        failed_assets: 0,
        active_asset_id: null,
        bytes_uploaded: 0,
        sha1_elapsed_ms: 0,
        sha1_measured_assets: 0,
        started_at_ms,
      }),
    });
    throw_if_transfer_stopped();
    const trust_proof = await deps.trust_proof_signer.derive_trust_proof({
      purpose: 'capabilities.exchange',
      schema: 'dtis.mobile-capabilities.v1',
      session_id,
      device_uuid,
      trust_key_b64,
    });
    let exchange_attempt = 0;
    let exchange: Awaited<ReturnType<CapabilityExchangeService['exchange']>> | null = null;
    let capability_exchange_error: Error | null = null;
    while (exchange == null && exchange_attempt < CAPABILITY_EXCHANGE_MAX_ATTEMPTS) {
      exchange_attempt += 1;
      try {
        exchange = await deps.capability_exchange_service.exchange({
          endpoint_base_url,
          session_id,
          device_uuid,
          trust_proof,
          capabilities: {
            [TRANSFER_ENCRYPTION_CAPABILITY]: 1,
          },
        });
      } catch (error) {
        capability_exchange_error = error instanceof Error ? error : new Error('Capability exchange failed.');
        if (exchange_attempt < CAPABILITY_EXCHANGE_MAX_ATTEMPTS) {
          throw_if_transfer_stopped();
          await delay(CAPABILITY_EXCHANGE_RETRY_DELAY_MS);
          continue;
        }
      }
    }
    if (exchange == null) {
      throw capability_exchange_error ?? new Error('Capability exchange failed.');
    }
    if (exchange.status !== 'accepted') {
      throw new Error(exchange.message || 'Capability exchange rejected.');
    }
    const supports_transfer_encryption = exchange.capabilities[TRANSFER_ENCRYPTION_CAPABILITY] === 1;
    if (strict_security_enabled && !supports_transfer_encryption) {
      throw new Error('Desktop does not support encrypted transfer required by strict security.');
    }
    useBackupSessionStore.getState().setPairingSession({
      ...pairing_session,
      encryptionEnabled: supports_transfer_encryption,
    });
    const supports_asset_version_existence =
      exchange.capabilities[TRANSFER_EXISTENCE_ASSET_VERSION_CAPABILITY] === 1;
    throw_if_transfer_stopped();

    const transfer_service = new TransferService({
      endpoint_base_url,
      session_id,
      device_uuid,
      trust_key_b64,
      encryption_enabled: supports_transfer_encryption,
    });
    const assets = await deps.transfer_asset_source.enumerate_normalized(5000);
    throw_if_transfer_stopped();
    const total_assets = assets.length;
    await transfer_service.start(total_assets, transfer_abort_signal);
    throw_if_transfer_stopped();
    await begin_transfer_runtime_session(deps.transfer_runtime_wiring);
    runtime_started = true;
    await deps.apply_command({ type: 'startTransfer' });

    await deps.apply_command({
      type: 'transferSnapshotUpdated',
      snapshot: build_snapshot({
        stage: TransferPipelineStage.Enumerating,
        total_assets,
        matched_assets: 0,
        transferred_assets: 0,
        failed_assets: 0,
        active_asset_id: null,
        bytes_uploaded: 0,
        sha1_elapsed_ms: 0,
        sha1_measured_assets: 0,
        started_at_ms,
      }),
    });

    let transferred_assets = 0;
    let failed_assets = 0;
    let bytes_uploaded = 0;
    let matched_assets = 0;
    let sha1_elapsed_ms = 0;
    let sha1_measured_assets = 0;

    const publish_snapshot = async (
      stage: TransferPipelineStage,
      active_asset_id: string | null
    ): Promise<void> => {
      await deps.apply_command({
        type: 'transferSnapshotUpdated',
        snapshot: build_snapshot({
          stage,
          total_assets,
          matched_assets,
          transferred_assets,
          failed_assets,
          active_asset_id,
          bytes_uploaded,
          sha1_elapsed_ms,
          sha1_measured_assets,
          started_at_ms,
        }),
      });
    };

    const prepare_existence_candidate = async (
      asset: NormalizedTransferAsset
    ): Promise<TransferAssetSignature | null> => {
      throw_if_transfer_stopped();
      const has_asset_version = supports_asset_version_existence && typeof asset.metadata.asset_version === 'string';
      const has_legacy_signature_shape =
        typeof asset.dedupe_signature.file_size_bytes === 'number' && asset.dedupe_signature.created_at != null;
      let content_sha1 = asset.dedupe_signature.content_sha1;
      if (!has_asset_version && content_sha1 == null && has_legacy_signature_shape) {
        const sha1_started_at_ms = Date.now();
        content_sha1 = await compute_asset_sha1(
          asset.asset_id,
          deps.transfer_asset_source,
          throw_if_transfer_stopped
        );
        sha1_elapsed_ms += Math.max(0, Date.now() - sha1_started_at_ms);
        sha1_measured_assets += 1;
        asset.dedupe_signature.content_sha1 = content_sha1;
        asset.metadata.sha1 = content_sha1;
      }
      const has_legacy_signature = content_sha1 != null && has_legacy_signature_shape;
      if (!has_asset_version && !has_legacy_signature) {
        return null;
      }
      return {
        asset_id: asset.asset_id,
        asset_version: has_asset_version ? asset.metadata.asset_version : undefined,
        sha1: content_sha1 ?? undefined,
        file_size: asset.dedupe_signature.file_size_bytes ?? undefined,
        created_at: asset.dedupe_signature.created_at ?? undefined,
      };
    };

    const upload_asset = async (asset: (typeof assets)[number]): Promise<void> => {
      throw_if_transfer_stopped();
      await publish_snapshot(TransferPipelineStage.Transferring, asset.asset_id);
      try {
        const chunk_reader = await deps.transfer_asset_source.open_asset_chunk_reader(asset.asset_id, 0);
        let asset_bytes_uploaded = 0;
        let upload_response;
        try {
          upload_response = await transfer_service.upload_asset_chunked(
            asset.metadata,
            async (_offset, length) => {
              throw_if_transfer_stopped();
              return chunk_reader.read_chunk(length);
            },
            typeof asset.metadata.file_size === 'number' && asset.metadata.file_size > 0
              ? asset.metadata.file_size
              : undefined,
            1024 * 1024,
            transfer_abort_signal,
            async (chunk_length) => {
              asset_bytes_uploaded += chunk_length;
              await publish_snapshot(TransferPipelineStage.Transferring, asset.asset_id);
            }
          );
        } finally {
          chunk_reader.close();
        }
        if (upload_response?.status === 'skipped') {
          matched_assets += 1;
          await publish_snapshot(TransferPipelineStage.Transferring, asset.asset_id);
          return;
        }
        bytes_uploaded += asset_bytes_uploaded;
        transferred_assets += 1;
        await publish_snapshot(TransferPipelineStage.Transferring, asset.asset_id);
      } catch (error) {
        failed_assets += 1;
        const message = error instanceof Error ? error.message : 'Unknown upload error.';
        throw new Error(`Failed uploading asset ${asset.asset_id}: ${message}`);
      }
    };

    type PreparedAssetWork = {
      asset: NormalizedTransferAsset;
      signature: TransferAssetSignature;
    };
    const prepared_asset_queue = new AsyncQueue<PreparedAssetWork>();
    const upload_asset_queue = new AsyncQueue<NormalizedTransferAsset>();
    let prepare_next_index = 0;
    let pipeline_error: Error | null = null;

    const fail_pipeline = (error: unknown): void => {
      if (pipeline_error != null) {
        return;
      }
      pipeline_error = error instanceof Error ? error : new Error('Transfer pipeline failed unexpectedly.');
      if (!transfer_abort_signal.aborted) {
        aborted_by_pipeline_error = true;
        options.abort_controller.abort();
      }
      prepared_asset_queue.close();
      upload_asset_queue.close();
    };

    const prepare_worker_count = Math.min(TRANSFER_CONCURRENT_SHA1_LIMIT, Math.max(1, assets.length));
    const prepare_workers = Array.from({ length: prepare_worker_count }, async () => {
      while (pipeline_error == null) {
        throw_if_transfer_stopped();
        const current_index = prepare_next_index;
        prepare_next_index += 1;
        if (current_index >= assets.length) {
          break;
        }
        const asset = assets[current_index];
        try {
          const signature = await prepare_existence_candidate(asset);
          if (signature) {
            prepared_asset_queue.push({ asset, signature });
          } else {
            upload_asset_queue.push(asset);
          }
        } catch (error) {
          fail_pipeline(error);
        }
      }
    });

    const existence_worker = (async () => {
      const pending: PreparedAssetWork[] = [];
      while (pipeline_error == null) {
        const next_prepared = await prepared_asset_queue.shift();
        if (next_prepared !== undefined) {
          pending.push(next_prepared);
        }
        let next_buffered = prepared_asset_queue.tryShift();
        while (next_buffered !== undefined && pending.length < TRANSFER_EXISTENCE_BATCH_SIZE) {
          pending.push(next_buffered);
          next_buffered = prepared_asset_queue.tryShift();
        }
        if (pending.length === 0) {
          if (next_prepared === undefined) {
            break;
          }
          continue;
        }
        const batch = pending.splice(0, TRANSFER_EXISTENCE_BATCH_SIZE);
        try {
          await publish_snapshot(TransferPipelineStage.ExistingCheck, null);
          const existence = await transfer_service.check_existence(
            batch.map((item) => item.signature),
            transfer_abort_signal
          );
          throw_if_transfer_stopped();
          const matched_asset_ids = new Set<string>();
          for (const match of existence.matches ?? []) {
            matched_asset_ids.add(match.asset_id);
          }
          if (matched_asset_ids.size > 0) {
            matched_assets += matched_asset_ids.size;
          }
          for (const item of batch) {
            if (!matched_asset_ids.has(item.asset.asset_id)) {
              upload_asset_queue.push(item.asset);
            }
          }
          await publish_snapshot(TransferPipelineStage.ExistingCheck, null);
        } catch (error) {
          fail_pipeline(error);
          break;
        }
      }
      upload_asset_queue.close();
    })();

    const upload_worker_count = Math.min(TRANSFER_CONCURRENT_UPLOAD_LIMIT, Math.max(1, assets.length));
    const upload_workers = Array.from({ length: upload_worker_count }, async () => {
      while (pipeline_error == null) {
        const next_asset = await upload_asset_queue.shift();
        if (next_asset === undefined) {
          break;
        }
        try {
          await upload_asset(next_asset);
        } catch (error) {
          fail_pipeline(error);
        }
      }
    });

    await Promise.all(prepare_workers);
    prepared_asset_queue.close();
    await existence_worker;
    await Promise.all(upload_workers);
    if (pipeline_error) {
      throw pipeline_error;
    }

    await deps.apply_command({
      type: 'transferSnapshotUpdated',
      snapshot: build_snapshot({
        stage: TransferPipelineStage.Completing,
        total_assets,
        matched_assets,
        transferred_assets,
        failed_assets,
        active_asset_id: null,
        bytes_uploaded,
        sha1_elapsed_ms,
        sha1_measured_assets,
        started_at_ms,
      }),
    });

    await transfer_service.complete(transferred_assets, failed_assets, transfer_abort_signal);
    throw_if_transfer_stopped();
    await end_transfer_runtime_session(deps.transfer_runtime_wiring);
    runtime_started = false;
  } catch (error) {
    if (runtime_started) {
      await end_transfer_runtime_session(deps.transfer_runtime_wiring);
    }
    if (!aborted_by_pipeline_error && (transfer_abort_signal.aborted || is_transfer_abort_error(error))) {
      throw create_transfer_abort_error();
    }
    const message = error instanceof Error ? error.message : 'Transfer failed unexpectedly.';
    await deps.apply_command({
      type: 'transferResolved',
      result: {
        kind: 'failure',
        reason: TransferFailureReason.Unknown,
        error: {
          title: 'Transfer failed',
          message,
        },
      },
    });
    throw error;
  }
}
