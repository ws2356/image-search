import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';

export interface SubmitScannedPayloadDeps {
  apply_command: typeof apply_backup_command;
}

export async function submitScannedPayload(
  payload: PairingQRCodePayload,
  deps: SubmitScannedPayloadDeps = {
    apply_command: apply_backup_command,
  }
): Promise<void> {
  await deps.apply_command({ type: 'submitPairingPayload', payload });
}
