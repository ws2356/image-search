import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import {
  end_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';

export interface StopTransferDeps {
  apply_command: typeof apply_backup_command;
  transfer_runtime_wiring: TransferRuntimeWiring;
}

export async function stopTransfer(
  deps: StopTransferDeps = {
    apply_command: apply_backup_command,
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
  }
): Promise<void> {
  await end_transfer_runtime_session(deps.transfer_runtime_wiring);
  await deps.apply_command({ type: 'stopTransfer' });
}
