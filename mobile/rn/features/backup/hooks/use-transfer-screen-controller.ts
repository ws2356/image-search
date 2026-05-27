import { useRouter } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert } from 'react-native';
import { useBackupExitGuard } from '@/features/backup/hooks/use-backup-exit-guard';
import { PermissionScope } from '@/features/backup/preflight/enums';
import { persist_home_summary } from '@/features/backup/services/pairing-persistence-service';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { build_home_summary_from_session } from '@/features/backup/session/home-summary';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { useTransferStore } from '@/features/backup/store/transfer-store';
import { is_transfer_abort_error } from '@/features/backup/transfer/transfer-abort';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';
import { finishTransfer } from '@/features/backup/use-cases/finish-transfer';
import { returnHome } from '@/features/backup/use-cases/return-home';
import { startTransfer } from '@/features/backup/use-cases/start-transfer';
import { stopTransfer } from '@/features/backup/use-cases/stop-transfer';
import {
  add_android_transfer_session_listener,
  clear_android_transfer_session_state,
  get_current_android_transfer_session_state,
  is_android_headless_transfer_supported,
  request_stop_android_headless_transfer_session,
  start_android_headless_transfer_session,
  type AndroidTransferSessionState,
} from '@/infrastructure/platform/android-transfer-service';
import { create_default_app_awake_policy } from '@/infrastructure/system/app-awake-policy';

export interface TransferScreenController {
  transfer_running: boolean;
  transfer_error: string | null;
  transfer_snapshot: TransferProgressSnapshot | null;
  is_incomplete_library: boolean;
  confirm_stop: () => void;
  recover_transfer: () => Promise<void>;
  complete_transfer: () => Promise<void>;
}

const TRANSFER_SCREEN_SNAPSHOT_INTERVAL_MS = 1000;

export function useTransferScreenController(): TransferScreenController {
  const router = useRouter();
  const app_awake_policy = useMemo(create_default_app_awake_policy, []);
  const is_incomplete_library = useBackupSessionStore(
    (state) => state.session.permissionSummary.mediaScope !== PermissionScope.Full
  );
  const transfer_running = useTransferStore((state) => state.is_running);
  const transfer_error = useTransferStore((state) => state.last_error);
  const set_running = useTransferStore((state) => state.set_running);
  const set_last_error = useTransferStore((state) => state.set_last_error);
  const start_attempted_ref = useRef(false);
  const transfer_abort_controller_ref = useRef<AbortController | null>(null);
  const android_stop_requested_ref = useRef(false);
  const android_terminal_status_ref = useRef<AndroidTransferSessionState['status'] | null>(null);
  const transfer_snapshot_timeout_ref = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latest_transfer_snapshot_ref = useRef<TransferProgressSnapshot | null>(
    useBackupSessionStore.getState().session.transferSnapshot
  );
  const last_transfer_snapshot_flush_at_ref = useRef(0);
  const [transfer_snapshot, set_transfer_snapshot] = useState<TransferProgressSnapshot | null>(
    latest_transfer_snapshot_ref.current
  );

  const clear_transfer_abort_controller = (controller: AbortController | null) => {
    if (controller && transfer_abort_controller_ref.current === controller) {
      transfer_abort_controller_ref.current = null;
    }
  };

  async function handle_android_transfer_state(
    state: AndroidTransferSessionState | null,
    navigate_without_exit_prompt: (callback: () => void) => void
  ): Promise<void> {
    if (state == null) {
      return;
    }

    if (state.snapshot != null) {
      useBackupSessionStore.getState().setTransferSnapshot(state.snapshot);
    }

    if (state.status === 'running') {
      android_terminal_status_ref.current = null;
      set_running(true);
      return;
    }

    if (android_terminal_status_ref.current === state.status) {
      return;
    }
    android_terminal_status_ref.current = state.status;
    set_running(false);

    if (state.status === 'completed') {
      set_last_error(null);
      navigate_without_exit_prompt(() => {
        router.replace('/completed');
      });
      return;
    }

    if (state.status === 'failed') {
      set_last_error(state.errorMessage ?? 'Transfer failed unexpectedly.');
      return;
    }

    if (state.status === 'stopped') {
      if (android_stop_requested_ref.current) {
        android_stop_requested_ref.current = false;
        set_last_error(null);
        const store = useBackupSessionStore.getState();
        const home_summary = build_home_summary_from_session(store.session, {
          interruption_warning: 'Backup was stopped before completion.',
          last_backup_prefix: 'Stopped after ',
        });
        store.setHomeSummary(home_summary);
        await persist_home_summary(home_summary);
        await clear_android_transfer_session_state();
        await returnHome();
        navigate_without_exit_prompt(() => {
          router.replace('/');
        });
        return;
      }
      set_last_error('Transfer stopped.');
    }
  }

  async function stop_and_return_home(
    navigate_without_exit_prompt: (callback: () => void) => void
  ): Promise<void> {
    try {
      if (is_android_headless_transfer_supported()) {
        android_stop_requested_ref.current = true;
        android_terminal_status_ref.current = null;
        await request_stop_android_headless_transfer_session();
        return;
      }

      await stopTransfer({ abort_controller: transfer_abort_controller_ref.current });
      set_running(false);
      set_last_error(null);
      await returnHome();
      navigate_without_exit_prompt(() => {
        router.replace('/');
      });
    } catch (error) {
      android_stop_requested_ref.current = false;
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
            void stop_and_return_home(navigate_without_exit_prompt);
          },
        },
      ]
    );
  }

  const navigate_without_exit_prompt = useBackupExitGuard(confirm_stop);

  useEffect(() => {
    const flush_transfer_snapshot = (snapshot: TransferProgressSnapshot | null) => {
      latest_transfer_snapshot_ref.current = snapshot;
      last_transfer_snapshot_flush_at_ref.current = Date.now();
      set_transfer_snapshot(snapshot);
    };

    const clear_pending_transfer_snapshot = () => {
      if (transfer_snapshot_timeout_ref.current != null) {
        clearTimeout(transfer_snapshot_timeout_ref.current);
        transfer_snapshot_timeout_ref.current = null;
      }
    };

    const schedule_transfer_snapshot_flush = () => {
      if (transfer_snapshot_timeout_ref.current != null) {
        return;
      }
      const elapsed_ms = Date.now() - last_transfer_snapshot_flush_at_ref.current;
      const delay_ms = Math.max(0, TRANSFER_SCREEN_SNAPSHOT_INTERVAL_MS - elapsed_ms);
      transfer_snapshot_timeout_ref.current = setTimeout(() => {
        transfer_snapshot_timeout_ref.current = null;
        flush_transfer_snapshot(latest_transfer_snapshot_ref.current);
      }, delay_ms);
    };

    const unsubscribe = useBackupSessionStore.subscribe((state, previous_state) => {
      const next_snapshot = state.session.transferSnapshot;
      if (next_snapshot === previous_state.session.transferSnapshot) {
        return;
      }
      latest_transfer_snapshot_ref.current = next_snapshot;
      const elapsed_ms = Date.now() - last_transfer_snapshot_flush_at_ref.current;
      if (
        last_transfer_snapshot_flush_at_ref.current === 0 ||
        elapsed_ms >= TRANSFER_SCREEN_SNAPSHOT_INTERVAL_MS
      ) {
        clear_pending_transfer_snapshot();
        flush_transfer_snapshot(next_snapshot);
        return;
      }
      schedule_transfer_snapshot_flush();
    });

    return () => {
      unsubscribe();
      clear_pending_transfer_snapshot();
    };
  }, []);

  useEffect(() => {
    void app_awake_policy.set_awake_enabled(transfer_running);
    return () => {
      void app_awake_policy.set_awake_enabled(false);
    };
  }, [app_awake_policy, transfer_running]);

  useEffect(() => {
    if (!is_android_headless_transfer_supported()) {
      return;
    }

    const subscription = add_android_transfer_session_listener((state) => {
      void handle_android_transfer_state(state, navigate_without_exit_prompt);
    });

    return () => {
      subscription.remove();
    };
  }, [navigate_without_exit_prompt, router, set_last_error, set_running]);

  useEffect(() => {
    if (start_attempted_ref.current) {
      return;
    }
    start_attempted_ref.current = true;
    set_last_error(null);
    set_running(true);

    if (is_android_headless_transfer_supported()) {
      void (async () => {
        const session = useBackupSessionStore.getState().session;
        const current_state = await get_current_android_transfer_session_state();
        if (current_state?.status === 'running') {
          await handle_android_transfer_state(current_state, navigate_without_exit_prompt);
          return;
        }
        if (current_state != null && current_state.status !== 'idle') {
          await clear_android_transfer_session_state();
        }

        if (!session.pairingSession || !session.localDeviceIdentity) {
          set_running(false);
          set_last_error('Transfer unavailable. Pair a desktop first.');
          return;
        }

        await start_android_headless_transfer_session({
          pairingSession: session.pairingSession,
          localDeviceIdentity: session.localDeviceIdentity,
        });
      })().catch((error) => {
        const message = error instanceof Error ? error.message : 'Failed to start transfer.';
        set_running(false);
        set_last_error(message);
      });

      return;
    }

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
        router.replace('/scan');
      });
    },
    complete_transfer: async () => {
      try {
        await finishTransfer();
        set_running(false);
        navigate_without_exit_prompt(() => {
          router.replace('/completed');
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to complete transfer.';
        set_last_error(message);
      }
    },
  };
}
