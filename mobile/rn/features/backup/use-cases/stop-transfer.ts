import {
  MOBILE_TRANSFER_INTERRUPTION_REASON_STOPPED_BY_USER,
} from '@/features/backup/protocols/transfer';
import { TransferService } from '@/features/backup/services/transfer-service';
import { persist_home_summary } from '@/features/backup/services/pairing-persistence-service';
import { build_home_summary_from_session } from '@/features/backup/session/home-summary';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import {
  end_transfer_runtime_session,
  get_default_transfer_runtime_wiring,
  type TransferRuntimeWiring,
} from '@/infrastructure/platform/transfer-runtime-wiring';

export interface StopTransferDeps {
  transfer_runtime_wiring: TransferRuntimeWiring;
}

export interface StopTransferOptions {
  abort_controller?: AbortController | null;
}

export async function stopTransfer(
  options: StopTransferOptions = {},
  deps: StopTransferDeps = {
    transfer_runtime_wiring: get_default_transfer_runtime_wiring(),
  }
): Promise<void> {
  const session = useBackupSessionStore.getState().session;
  const session_id = session.pairingSession?.sessionId;
  const endpoint_base_url = session.pairingSession?.endpointBaseUrl;
  const trust_key_b64 = session.pairingSession?.trustKeyB64;
  const encryption_enabled = session.pairingSession?.encryptionEnabled === true;
  const device_uuid = session.localDeviceIdentity?.deviceUuid;
  const transferred_count = session.transferSnapshot?.counts.transferredAssets ?? 0;
  const failed_count = session.transferSnapshot?.counts.failedAssets ?? 0;

  options.abort_controller?.abort();
  let notify_error: Error | null = null;
  if (session_id && endpoint_base_url && trust_key_b64 && device_uuid) {
    try {
      const transfer_service = new TransferService({
        endpoint_base_url,
        session_id,
        device_uuid,
        trust_key_b64,
        encryption_enabled,
      });
      await transfer_service.complete(
        transferred_count,
        failed_count,
        undefined,
        MOBILE_TRANSFER_INTERRUPTION_REASON_STOPPED_BY_USER
      );
    } catch (error) {
      notify_error = error instanceof Error ? error : new Error('Failed to notify desktop about stop request.');
    }
  }
  const home_summary = build_home_summary_from_session(session, {
    interruption_warning: 'Backup was stopped before completion.',
    last_backup_prefix: 'Stopped after ',
  });
  useBackupSessionStore.getState().setHomeSummary(home_summary);
  await persist_home_summary(home_summary);
  await end_transfer_runtime_session(deps.transfer_runtime_wiring);
  if (notify_error) {
    throw notify_error;
  }
}
