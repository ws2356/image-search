import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { persist_home_summary } from '@/features/backup/services/pairing-persistence-service';
import { build_home_summary_from_session } from '@/features/backup/session/home-summary';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import {
  end_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';

export interface FinishTransferDeps {
  apply_command: typeof apply_backup_command;
  transfer_runtime_wiring: TransferRuntimeWiring;
}

export async function finishTransfer(
  deps: FinishTransferDeps = {
    apply_command: apply_backup_command,
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
  }
): Promise<void> {
const store = useBackupSessionStore.getState();
const home_summary = build_home_summary_from_session(store.session, { interruption_warning: null });
store.setHomeSummary(home_summary);
await persist_home_summary(home_summary);
await deps.apply_command({
    type: 'transferResolved',
    result: {
      kind: 'success',
      completedAt: new Date().toISOString(),
    },
  });
  await deps.apply_command({ type: 'completeTransfer' });
  await end_transfer_runtime_session(deps.transfer_runtime_wiring);
}
