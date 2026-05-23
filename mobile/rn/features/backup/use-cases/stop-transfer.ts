import type { BackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';

export interface StopTransferDeps {
  orchestrator: BackupFlowOrchestrator;
}

export async function stopTransfer(
  deps: StopTransferDeps = { orchestrator: createBackupFlowOrchestrator() }
): Promise<void> {
  await deps.orchestrator.stopTransfer();
}
