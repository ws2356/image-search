import { useRouter } from 'expo-router';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { useTransferStore } from '@/features/backup/store/transfer-store';
import { finishTransfer } from '@/features/backup/use-cases/finish-transfer';
import { startTransfer } from '@/features/backup/use-cases/start-transfer';
import { stopTransfer } from '@/features/backup/use-cases/stop-transfer';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';

export interface TransferScreenController {
  transfer_running: boolean;
  transfer_error: string | null;
  transfer_snapshot_label: string;
  start_live_transfer: () => Promise<void>;
  stop_live_transfer: () => Promise<void>;
  recover_transfer: () => Promise<void>;
  complete_transfer: () => Promise<void>;
  go_completed: () => void;
  go_error: () => void;
  open_incoming_link_replacement: () => void;
  open_transfer_simulator: () => void;
}

export function useTransferScreenController(): TransferScreenController {
  const router = useRouter();
  const transfer_snapshot = useBackupSessionStore((state) => state.session.transferSnapshot);
  const transfer_running = useTransferStore((state) => state.is_running);
  const transfer_error = useTransferStore((state) => state.last_error);
  const set_running = useTransferStore((state) => state.set_running);
  const set_last_error = useTransferStore((state) => state.set_last_error);

  const transfer_snapshot_label = transfer_snapshot
    ? `${transfer_snapshot.pipelineStage} | ${transfer_snapshot.counts.transferredAssets}/${transfer_snapshot.counts.totalAssets} transferred`
    : 'No transfer snapshot yet.';

  return {
    transfer_running,
    transfer_error,
    transfer_snapshot_label,
    start_live_transfer: async () => {
      try {
        set_last_error(null);
        set_running(true);
        await startTransfer();
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to start transfer.';
        set_last_error(message);
        set_running(false);
      }
    },
    stop_live_transfer: async () => {
      try {
        await stopTransfer();
        set_running(false);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to stop transfer.';
        set_last_error(message);
      }
    },
    recover_transfer: async () => {
      await apply_backup_command({ type: 'recoverFromError' });
      set_last_error(null);
      set_running(false);
      router.push('/scan');
    },
    complete_transfer: async () => {
      try {
        await finishTransfer();
        set_running(false);
        router.push('/completed');
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to complete transfer.';
        set_last_error(message);
      }
    },
    go_completed: () => router.push('/completed'),
    go_error: () => router.push('/error'),
    open_incoming_link_replacement: () => router.push('/incoming-link-replacement'),
    open_transfer_simulator: () => router.push('/transfer-simulator'),
  };
}
