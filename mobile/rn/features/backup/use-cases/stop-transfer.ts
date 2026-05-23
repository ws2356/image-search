import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';

export interface StopTransferDeps {
  apply_command: typeof apply_backup_command;
}

export async function stopTransfer(
  deps: StopTransferDeps = { apply_command: apply_backup_command }
): Promise<void> {
  await deps.apply_command({ type: 'stopTransfer' });
}
