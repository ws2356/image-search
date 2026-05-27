import QuickCrypto from 'react-native-quick-crypto';
import { assert_transfer_not_live_in_phase4 } from '@/features/backup/services/phase-scope';
import { TransferService } from '@/features/backup/services/transfer-service';
import type { CapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { DefaultTransferAssetSource, type TransferAssetSource } from '@/features/backup/services/transfer-asset-source';
import { TRANSFER_EXISTENCE_ASSET_VERSION_CAPABILITY } from '@/features/backup/protocols/capabilities';
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
  if (!session.pairingSession?.sessionId || !session.pairingSession.endpointBaseUrl) {
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
  const trust_key_b64 = session.pairingSession.trustKeyB64;
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

  const session_id = session.pairingSession.sessionId;
  const endpoint_base_url = session.pairingSession.endpointBaseUrl;
  const started_at_ms = Date.now();
  let runtime_started = false;
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
    const exchange = await deps.capability_exchange_service.exchange({
      endpoint_base_url,
      session_id,
      device_uuid,
      trust_proof,
      capabilities: {
        encrypted_payload_v1: 1,
      },
    });
    if (exchange.status !== 'accepted') {
      throw new Error(exchange.message || 'Capability exchange rejected.');
    }
    const supports_asset_version_existence =
      exchange.capabilities[TRANSFER_EXISTENCE_ASSET_VERSION_CAPABILITY] === 1;
    throw_if_transfer_stopped();

    const transfer_service = new TransferService({
      endpoint_base_url,
      session_id,
      device_uuid,
      trust_key_b64,
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

    const build_existence_candidates = async (
      batch_assets: typeof assets
    ): Promise<TransferAssetSignature[]> => {
      const candidates: TransferAssetSignature[] = [];
      for (const asset of batch_assets) {
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
          continue;
        }
        candidates.push({
          asset_id: asset.asset_id,
          asset_version: has_asset_version ? asset.metadata.asset_version : undefined,
          sha1: content_sha1 ?? undefined,
          file_size: asset.dedupe_signature.file_size_bytes ?? undefined,
          created_at: asset.dedupe_signature.created_at ?? undefined,
        });
      }
      return candidates;
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

    const upload_ready_assets = async (ready_assets: typeof assets): Promise<void> => {
      let next_ready_index = 0;
      let upload_error: Error | null = null;
      const worker_count = Math.min(TRANSFER_CONCURRENT_UPLOAD_LIMIT, ready_assets.length);
      const workers = Array.from({ length: worker_count }, async () => {
        while (next_ready_index < ready_assets.length && upload_error == null) {
          const asset = ready_assets[next_ready_index];
          next_ready_index += 1;
          await upload_asset(asset).catch((error) => {
            upload_error = error instanceof Error ? error : new Error('Unknown upload error.');
          });
        }
      });
      await Promise.all(workers);
      if (upload_error) {
        throw upload_error;
      }
    };

    for (let batch_start = 0; batch_start < assets.length; batch_start += TRANSFER_EXISTENCE_BATCH_SIZE) {
      throw_if_transfer_stopped();
      const batch_assets = assets.slice(batch_start, batch_start + TRANSFER_EXISTENCE_BATCH_SIZE);
      const existence_candidates = await build_existence_candidates(batch_assets);
      const matched_asset_ids = new Set<string>();
      await publish_snapshot(TransferPipelineStage.ExistingCheck, null);
      if (existence_candidates.length > 0) {
        const existence = await transfer_service.check_existence(existence_candidates, transfer_abort_signal);
        throw_if_transfer_stopped();
        for (const match of existence.matches ?? []) {
          matched_asset_ids.add(match.asset_id);
        }
      }
      if (matched_asset_ids.size > 0) {
        matched_assets += matched_asset_ids.size;
      }
      await publish_snapshot(TransferPipelineStage.ExistingCheck, null);
      const ready_assets = batch_assets.filter((asset) => !matched_asset_ids.has(asset.asset_id));
      if (ready_assets.length === 0) {
        continue;
      }
      await upload_ready_assets(ready_assets);
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
    if (transfer_abort_signal.aborted || is_transfer_abort_error(error)) {
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
