import type { BackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';

export interface FinishTransferDeps {
  orchestrator: BackupFlowOrchestrator;
}

export async function finishTransfer(
  deps: FinishTransferDeps = { orchestrator: createBackupFlowOrchestrator() }
): Promise<void> {
  await deps.orchestrator.execute({
    type: 'transferResolved',
    result: {
      kind: 'success',
      completedAt: new Date().toISOString(),
    },
  });
  await deps.orchestrator.completeTransfer();
}
