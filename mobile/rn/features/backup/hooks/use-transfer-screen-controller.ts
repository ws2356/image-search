import { useRouter } from 'expo-router';
import { useEffect, useMemo } from 'react';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { useTransferStore } from '@/features/backup/store/transfer-store';
import { finishTransfer } from '@/features/backup/use-cases/finish-transfer';
import { stopTransfer } from '@/features/backup/use-cases/stop-transfer';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { create_default_app_awake_policy } from '@/infrastructure/system/app-awake-policy';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';

export interface TransferScreenController {
  transfer_running: boolean;
  transfer_error: string | null;
  transfer_snapshot: TransferProgressSnapshot | null;
  confirm_stop: () => Promise<void>;
  recover_transfer: () => Promise<void>;
  complete_transfer: () => Promise<void>;
}

export function useTransferScreenController(): TransferScreenController {
  const router = useRouter();
  const app_awake_policy = useMemo(create_default_app_awake_policy, []);
  const transfer_snapshot = useBackupSessionStore((state) => state.session.transferSnapshot);
  const transfer_running = useTransferStore((state) => state.is_running);
  const transfer_error = useTransferStore((state) => state.last_error);
  const set_running = useTransferStore((state) => state.set_running);
  const set_last_error = useTransferStore((state) => state.set_last_error);

  useEffect(() => {
    void app_awake_policy.set_awake_enabled(transfer_running);
    return () => {
      void app_awake_policy.set_awake_enabled(false);
    };
  }, [app_awake_policy, transfer_running]);

  return {
    transfer_running,
    transfer_error,
    transfer_snapshot,
    confirm_stop: async () => {
      try {
        await stopTransfer();
        set_running(false);
        router.push('/');
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
  };
}
