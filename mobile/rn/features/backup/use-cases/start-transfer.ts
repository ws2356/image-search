import { assert_transfer_not_live_in_phase4 } from '@/features/backup/services/phase-scope';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { TransferTransport, TransferPipelineStage } from '@/features/backup/transfer/enums';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import {
  begin_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';

export interface StartTransferDeps {
  apply_command: typeof apply_backup_command;
  trust_proof_signer: TrustProofSigner;
  transfer_runtime_wiring: TransferRuntimeWiring;
}

function build_initial_snapshot(now: Date): TransferProgressSnapshot {
  return {
    pipelineStage: TransferPipelineStage.Enumerating,
    transport: TransferTransport.Lan,
    counts: {
      totalAssets: 0,
      matchedAssets: 0,
      transferredAssets: 0,
      failedAssets: 0,
    },
    activeAssetId: null,
    activeRequestId: null,
    bytesUploaded: 0,
    bytesPerSecond: null,
    estimatedSecondsRemaining: null,
    lastUpdatedAt: now.toISOString(),
  };
}

export async function startTransfer(
  deps: StartTransferDeps = {
    apply_command: apply_backup_command,
    trust_proof_signer: {
      derive_trust_proof: async (input) =>
        `stub_trust_proof:${input.purpose}:${input.schema}:${input.session_id}:${input.device_uuid}`,
    },
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
  }
): Promise<void> {
  assert_transfer_not_live_in_phase4('startTransfer');
  await begin_transfer_runtime_session(deps.transfer_runtime_wiring);
  await deps.trust_proof_signer.derive_trust_proof({
    purpose: 'transfer.start',
    schema: 'dtis.mobile-transfer.v1',
    session_id: 'pending-session',
    device_uuid: 'pending-device',
  });
  await deps.apply_command({ type: 'startTransfer' });
  await deps.apply_command({
    type: 'transferSnapshotUpdated',
    snapshot: build_initial_snapshot(new Date()),
  });
}
