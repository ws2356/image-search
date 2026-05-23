import type { BackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { TransferTransport, TransferPipelineStage } from '@/features/backup/transfer/enums';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';

export interface StartTransferDeps {
  orchestrator: BackupFlowOrchestrator;
  trust_proof_signer: TrustProofSigner;
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
    orchestrator: createBackupFlowOrchestrator(),
    trust_proof_signer: {
      derive_trust_proof: async (input) =>
        `stub_trust_proof:${input.purpose}:${input.schema}:${input.session_id}:${input.device_uuid}`,
    },
  }
): Promise<void> {
  await deps.trust_proof_signer.derive_trust_proof({
    purpose: 'transfer.start',
    schema: 'dtis.mobile-transfer.v1',
    session_id: 'pending-session',
    device_uuid: 'pending-device',
  });
  await deps.orchestrator.startTransfer();
  await deps.orchestrator.execute({
    type: 'transferSnapshotUpdated',
    snapshot: build_initial_snapshot(new Date()),
  });
}
