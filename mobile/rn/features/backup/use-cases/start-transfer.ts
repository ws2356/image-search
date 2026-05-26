import { assert_transfer_not_live_in_phase4 } from '@/features/backup/services/phase-scope';
import { TransferService } from '@/features/backup/services/transfer-service';
import type { CapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { DefaultTransferAssetSource, type TransferAssetSource } from '@/features/backup/services/transfer-asset-source';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { TransferFailureReason, TransferPipelineStage, TransferTransport } from '@/features/backup/transfer/enums';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import type { TransferAssetSignature } from '@/features/backup/protocols/transfer';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import {
  begin_transfer_abort_controller,
  end_transfer_abort_controller,
  is_transfer_abort_error,
  transfer_abort_error,
} from '@/features/backup/transfer/transfer-abort-controller';
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

function build_snapshot(input: {
  stage: TransferPipelineStage;
  total_assets: number;
  matched_assets: number;
  transferred_assets: number;
  failed_assets: number;
  active_asset_id: string | null;
  bytes_uploaded: number;
  started_at_ms: number;
}): TransferProgressSnapshot {
  const elapsed_seconds = Math.max(1, (Date.now() - input.started_at_ms) / 1000);
  const remaining_assets = Math.max(0, input.total_assets - input.transferred_assets - input.failed_assets);
  const bytes_per_second = input.bytes_uploaded > 0 ? input.bytes_uploaded / elapsed_seconds : null;
  const estimated_seconds_remaining =
    bytes_per_second && bytes_per_second > 0 && remaining_assets > 0
      ? Math.ceil((remaining_assets * (input.bytes_uploaded / Math.max(1, input.transferred_assets))) / bytes_per_second)
      : null;
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
    lastUpdatedAt: new Date().toISOString(),
  };
}

export async function startTransfer(
  deps: StartTransferDeps = {
    apply_command: apply_backup_command,
    trust_proof_signer: new DefaultTrustProofSigner(),
    capability_exchange_service: new HttpCapabilityExchangeService(),
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
    transfer_asset_source: new DefaultTransferAssetSource(),
  }
): Promise<void> {
  assert_transfer_not_live_in_phase4('startTransfer');
  const transfer_abort_controller = begin_transfer_abort_controller();
  const transfer_abort_signal = transfer_abort_controller.signal;
  const throw_if_transfer_stopped = () => {
    if (transfer_abort_signal.aborted) {
      throw transfer_abort_error();
    }
  };
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

  try {
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
        started_at_ms,
      }),
    });

    const signatures: TransferAssetSignature[] = assets
      .filter(
        (asset) =>
          asset.dedupe_signature.content_sha1 &&
          typeof asset.dedupe_signature.file_size_bytes === 'number' &&
          asset.dedupe_signature.created_at
      )
      .map((asset) => ({
        asset_id: asset.asset_id,
        content_sha1: asset.dedupe_signature.content_sha1 as string,
        file_size_bytes: asset.dedupe_signature.file_size_bytes as number,
        created_at: asset.dedupe_signature.created_at as string,
      }));

    const matched_asset_ids = new Set<string>();
    if (signatures.length > 0) {
      const existence = await transfer_service.check_existence(signatures, transfer_abort_signal);
      throw_if_transfer_stopped();
      for (const match of existence.matches ?? []) {
        matched_asset_ids.add(match.asset_id);
      }
    }

    let transferred_assets = 0;
    let failed_assets = 0;
    let bytes_uploaded = 0;
    const matched_assets = matched_asset_ids.size;

    await deps.apply_command({
      type: 'transferSnapshotUpdated',
      snapshot: build_snapshot({
        stage: TransferPipelineStage.ExistingCheck,
        total_assets,
        matched_assets,
        transferred_assets,
        failed_assets,
        active_asset_id: null,
        bytes_uploaded,
        started_at_ms,
      }),
    });

    for (const asset of assets) {
      throw_if_transfer_stopped();
      if (matched_asset_ids.has(asset.asset_id)) {
        transferred_assets += 1;
      } else {
        try {
          const declared_size =
            typeof asset.metadata.file_size_bytes === 'number' && asset.metadata.file_size_bytes > 0
              ? asset.metadata.file_size_bytes
              : undefined;
          const chunk_reader = await deps.transfer_asset_source.open_asset_chunk_reader(asset.asset_id, 0);
          try {
            await transfer_service.upload_asset_chunked(
              asset.metadata,
              async (_offset, length) => chunk_reader.read_chunk(length),
              declared_size,
              1024 * 1024,
              transfer_abort_signal
            );
          } finally {
            chunk_reader.close();
          }
          if (typeof declared_size === 'number') {
            bytes_uploaded += declared_size;
          }
          transferred_assets += 1;
        } catch (error) {
          failed_assets += 1;
          const message = error instanceof Error ? error.message : 'Unknown upload error.';
          throw new Error(`Failed uploading asset ${asset.asset_id}: ${message}`);
        }
      }

      await deps.apply_command({
        type: 'transferSnapshotUpdated',
        snapshot: build_snapshot({
          stage: TransferPipelineStage.Transferring,
          total_assets,
          matched_assets,
          transferred_assets,
          failed_assets,
          active_asset_id: asset.asset_id,
          bytes_uploaded,
          started_at_ms,
        }),
      });
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
      return;
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
  } finally {
    end_transfer_abort_controller(transfer_abort_controller);
  }
}
