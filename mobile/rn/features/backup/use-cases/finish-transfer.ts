import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';

export interface FinishTransferDeps {
  apply_command: typeof apply_backup_command;
}

export async function finishTransfer(
  deps: FinishTransferDeps = { apply_command: apply_backup_command }
): Promise<void> {
  await deps.apply_command({
    type: 'transferResolved',
    result: {
      kind: 'success',
      completedAt: new Date().toISOString(),
    },
  });
  await deps.apply_command({ type: 'completeTransfer' });
}
