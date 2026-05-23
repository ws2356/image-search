import type { BackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import type { PairingQRCodePayload } from '@/features/backup/pairing/models';

export interface SubmitScannedPayloadDeps {
  orchestrator: BackupFlowOrchestrator;
}

export async function submitScannedPayload(
  payload: PairingQRCodePayload,
  deps: SubmitScannedPayloadDeps = {
    orchestrator: createBackupFlowOrchestrator(),
  }
): Promise<void> {
  await deps.orchestrator.execute({ type: 'submitPairingPayload', payload });
}
