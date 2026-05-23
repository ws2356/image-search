import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';

export interface ReturnHomeDeps {
  apply_command: typeof apply_backup_command;
}

export async function returnHome(
  deps: ReturnHomeDeps = { apply_command: apply_backup_command }
): Promise<void> {
  await deps.apply_command({ type: 'returnHome' });
}
