import type { BackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';

export interface ReturnHomeDeps {
  orchestrator: BackupFlowOrchestrator;
}

export async function returnHome(
  deps: ReturnHomeDeps = { orchestrator: createBackupFlowOrchestrator() }
): Promise<void> {
  await deps.orchestrator.returnHome();
}
