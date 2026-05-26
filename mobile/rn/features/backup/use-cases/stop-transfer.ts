import {
  end_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';
import { abort_active_transfer } from '@/features/backup/transfer/transfer-abort-controller';

export interface StopTransferDeps {
  transfer_runtime_wiring: TransferRuntimeWiring;
}

export async function stopTransfer(
  deps: StopTransferDeps = {
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
  }
): Promise<void> {
  abort_active_transfer();
  await end_transfer_runtime_session(deps.transfer_runtime_wiring);
}
