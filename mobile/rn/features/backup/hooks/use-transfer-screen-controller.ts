import { useRouter } from 'expo-router';
import { useEffect, useMemo, useRef } from 'react';
import { Alert } from 'react-native';
import { useBackupExitGuard } from '@/features/backup/hooks/use-backup-exit-guard';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { useTransferStore } from '@/features/backup/store/transfer-store';
import { finishTransfer } from '@/features/backup/use-cases/finish-transfer';
import { startTransfer } from '@/features/backup/use-cases/start-transfer';
import { stopTransfer } from '@/features/backup/use-cases/stop-transfer';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { create_default_app_awake_policy } from '@/infrastructure/system/app-awake-policy';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import { PermissionScope } from '@/features/backup/preflight/enums';
import {
  is_transfer_abort_error,
} from '@/features/backup/transfer/transfer-abort';
import { returnHome } from '@/features/backup/use-cases/return-home';

export interface TransferScreenController {
  transfer_running: boolean;
  transfer_error: string | null;
  transfer_snapshot: TransferProgressSnapshot | null;
  is_incomplete_library: boolean;
  confirm_stop: () => void;
  recover_transfer: () => Promise<void>;
  complete_transfer: () => Promise<void>;
}

export function useTransferScreenController(): TransferScreenController {
  const router = useRouter();
  const app_awake_policy = useMemo(create_default_app_awake_policy, []);
  const transfer_snapshot = useBackupSessionStore((state) => state.session.transferSnapshot);
  const is_incomplete_library = useBackupSessionStore(
    (state) => state.session.permissionSummary.mediaScope !== PermissionScope.Full
  );
  const transfer_running = useTransferStore((state) => state.is_running);
  const transfer_error = useTransferStore((state) => state.last_error);
  const set_running = useTransferStore((state) => state.set_running);
  const set_last_error = useTransferStore((state) => state.set_last_error);
  const start_attempted_ref = useRef(false);
  const transfer_abort_controller_ref = useRef<AbortController | null>(null);

  async function stop_and_return_home(): Promise<void> {
    try {
      await stopTransfer({ abort_controller: transfer_abort_controller_ref.current });
      set_running(false);
      set_last_error(null);
      await returnHome();
      navigate_without_exit_prompt(() => {
        router.replace('/');
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to stop transfer.';
      set_last_error(message);
    }
  }

  function confirm_stop() {
    Alert.alert(
      'Stop backup?',
      'The desktop may continue indexing items that already transferred before the stop request.',
      [
        { text: 'Keep Backing Up', style: 'cancel' },
        {
          text: 'Stop Sending More Items',
          style: 'destructive',
          onPress: () => {
            void stop_and_return_home();
          },
        },
      ]
    );
  }
  const navigate_without_exit_prompt = useBackupExitGuard(confirm_stop);

  const clear_transfer_abort_controller = (controller: AbortController | null) => {
    if (controller && transfer_abort_controller_ref.current === controller) {
      transfer_abort_controller_ref.current = null;
    }
  };

  useEffect(() => {
    void app_awake_policy.set_awake_enabled(transfer_running);
    return () => {
      void app_awake_policy.set_awake_enabled(false);
    };
  }, [app_awake_policy, transfer_running]);

  useEffect(() => {
    if (start_attempted_ref.current) {
      return;
    }
    start_attempted_ref.current = true;
    set_last_error(null);
    set_running(true);
    const transfer_abort_controller = new AbortController();
    transfer_abort_controller_ref.current = transfer_abort_controller;
    void (async () => {
      try {
        await startTransfer({ abort_controller: transfer_abort_controller });
        set_running(false);
        navigate_without_exit_prompt(() => {
          router.replace('/completed');
        });
      } catch (error) {
        if (is_transfer_abort_error(error)) {
          set_running(false);
          return;
        }
        const message = error instanceof Error ? error.message : 'Failed to start transfer.';
        set_running(false);
        set_last_error(message);
      } finally {
        clear_transfer_abort_controller(transfer_abort_controller);
      }
    })();
    return () => {
      transfer_abort_controller.abort();
      clear_transfer_abort_controller(transfer_abort_controller);
    };
  }, [navigate_without_exit_prompt, router, set_last_error, set_running]);

  return {
    transfer_running,
    transfer_error,
    transfer_snapshot,
    is_incomplete_library,
    confirm_stop,
    recover_transfer: async () => {
      await apply_backup_command({ type: 'recoverFromError' });
      set_last_error(null);
      set_running(false);
      navigate_without_exit_prompt(() => {
        router.push('/scan');
      });
    },
    complete_transfer: async () => {
      try {
        await finishTransfer();
        set_running(false);
        navigate_without_exit_prompt(() => {
          router.push('/completed');
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to complete transfer.';
        set_last_error(message);
      }
    },
  };
}
