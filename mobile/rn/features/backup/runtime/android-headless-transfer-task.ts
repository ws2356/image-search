import type { BackupCommand } from '@/features/backup/state/backup-commands';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { is_transfer_abort_error } from '@/features/backup/transfer/transfer-abort';
import { startTransfer } from '@/features/backup/use-cases/start-transfer';
import { stopTransfer } from '@/features/backup/use-cases/stop-transfer';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import { DefaultTransferAssetSource } from '@/features/backup/services/transfer-asset-source';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import {
  clear_android_transfer_stop_request,
  is_android_transfer_stop_requested,
  publish_android_transfer_progress,
  publish_android_transfer_state,
  type AndroidHeadlessTransferTaskPayload,
} from '@/infrastructure/platform/android-transfer-service';
import { get_default_transfer_runtime_wiring } from '@/infrastructure/platform/transfer-runtime-wiring';

async function apply_headless_transfer_command(command: BackupCommand): Promise<void> {
  await apply_backup_command(command);
  if (command.type === 'transferSnapshotUpdated') {
    await publish_android_transfer_progress(command.snapshot);
  }
}

function hydrate_headless_transfer_session(task_payload: AndroidHeadlessTransferTaskPayload): void {
  const store = useBackupSessionStore.getState();
  store.setPairingSession(task_payload.pairingSession);
  store.setLocalDeviceIdentity(task_payload.localDeviceIdentity);
  store.setLatestError(null);
}

export async function run_android_headless_transfer_task(
  task_context: { taskPayloadJson?: string }
): Promise<void> {
  const task_payload_json = task_context.taskPayloadJson;
  if (typeof task_payload_json !== 'string') {
    throw new Error('Android headless transfer task is missing its payload.');
  }
  const task_payload = JSON.parse(task_payload_json) as AndroidHeadlessTransferTaskPayload;
  hydrate_headless_transfer_session(task_payload);
  await clear_android_transfer_stop_request();
  await publish_android_transfer_state({ status: 'running' });

  const abort_controller = new AbortController();
  let stop_watch_timer: ReturnType<typeof setInterval> | null = null;
  const clear_stop_watch_timer = () => {
    if (stop_watch_timer != null) {
      clearInterval(stop_watch_timer);
      stop_watch_timer = null;
    }
  };
  stop_watch_timer = setInterval(() => {
    if (!abort_controller.signal.aborted && is_android_transfer_stop_requested()) {
      abort_controller.abort();
    }
  }, 200);

  try {
    await startTransfer(
      {
        abort_controller,
        should_abort: is_android_transfer_stop_requested,
      },
      {
        apply_command: apply_headless_transfer_command,
        trust_proof_signer: new DefaultTrustProofSigner(),
        capability_exchange_service: new HttpCapabilityExchangeService(),
        transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
        transfer_asset_source: new DefaultTransferAssetSource(),
      }
    );
    await publish_android_transfer_state({ status: 'completed' });
  } catch (error) {
    if (abort_controller.signal.aborted || is_transfer_abort_error(error) || is_android_transfer_stop_requested()) {
      await stopTransfer({ abort_controller });
      await publish_android_transfer_state({ status: 'stopped' });
      return;
    }
    const message = error instanceof Error ? error.message : 'Transfer failed unexpectedly.';
    await publish_android_transfer_state({ status: 'failed', errorMessage: message });
    throw error;
  } finally {
    clear_stop_watch_timer();
    await clear_android_transfer_stop_request();
  }
}
