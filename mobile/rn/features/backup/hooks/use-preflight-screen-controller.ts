import { useRouter } from 'expo-router';
import { Alert } from 'react-native';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { useBackupExitGuard } from '@/features/backup/hooks/use-backup-exit-guard';
import { PreflightFailureReason, PermissionScope } from '@/features/backup/preflight/enums';
import type { PermissionSummary } from '@/features/backup/preflight/models';
import { create_default_preflight_service } from '@/features/backup/services/preflight-service';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { returnHome } from '@/features/backup/use-cases/return-home';
import { runPreflight } from '@/features/backup/use-cases/run-preflight';

export type PreflightPromptPhase = 'loading' | 'media' | 'low-battery' | 'remove-after-backup' | 'failed';

export interface PreflightScreenController {
  phase: PreflightPromptPhase;
  summary: PermissionSummary | null;
  error_message: string | null;
  request_media_access: () => Promise<void>;
  continue_without_media_update: () => Promise<void>;
  continue_past_low_battery: () => Promise<void>;
  cancel_from_low_battery: () => Promise<void>;
  choose_remove_after_backup: (enabled: boolean) => Promise<void>;
  return_home: () => void;
}

export function usePreflightScreenController(): PreflightScreenController {
  const router = useRouter();
  const preflight_service = useMemo(create_default_preflight_service, []);
  const [phase, set_phase] = useState<PreflightPromptPhase>('loading');
  const [summary, set_summary] = useState<PermissionSummary | null>(null);
  const [error_message, set_error_message] = useState<string | null>(null);
  const navigate_without_exit_prompt = useBackupExitGuard(() => {
    Alert.alert(
      'Leave backup setup?',
      'This will stop preflight and return to the backup home screen.',
      [
        { text: 'Keep Setting Up', style: 'cancel' },
        {
          text: 'Leave Setup',
          style: 'destructive',
          onPress: () => {
            void returnHome().then(() => {
              navigate_without_exit_prompt(() => {
                router.replace('/');
              });
            });
          },
        },
      ]
    );
  });

  const resolve_next_phase = useCallback((current_summary: PermissionSummary): PreflightPromptPhase => {
    if (current_summary.mediaScope !== PermissionScope.Full) {
      return 'media';
    }
    if (current_summary.lowBatteryWarningNeeded && !current_summary.isCharging) {
      return 'low-battery';
    }
    return 'remove-after-backup';
  }, []);

  const load_preflight_state = useCallback(async () => {
    try {
      set_error_message(null);
      console.log('[Preflight] Loading preflight state');
      const next_summary = await runPreflight({
        apply_command: apply_backup_command,
        preflight_service,
      });
      console.log('[Preflight] Loaded', { mediaScope: next_summary.mediaScope, isCharging: next_summary.isCharging });
      set_summary(next_summary);
      set_phase(resolve_next_phase(next_summary));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to run preflight checks.';
      console.log('[Preflight] Error', message);
      set_error_message(message);
      set_phase('failed');
    }
  }, [preflight_service, resolve_next_phase]);

  useEffect(() => {
    void load_preflight_state();
  }, [load_preflight_state]);

  const continue_after_media_step = useCallback(async () => {
    const refreshed = await preflight_service.load_permission_summary();
    set_summary(refreshed);
    if (refreshed.lowBatteryWarningNeeded && !refreshed.isCharging) {
      set_phase('low-battery');
      return;
    }
    set_phase('remove-after-backup');
  }, [preflight_service]);

  return {
    phase,
    summary,
    error_message,
    request_media_access: async () => {
      await preflight_service.request_media_access();
      await continue_after_media_step();
    },
    continue_without_media_update: async () => {
      await continue_after_media_step();
    },
    continue_past_low_battery: async () => {
      set_phase('remove-after-backup');
    },
    cancel_from_low_battery: async () => {
      await apply_backup_command({
        type: 'preflightResolved',
        result: {
          kind: 'failure',
          reason: PreflightFailureReason.LowBatteryDeclined,
          error: {
            title: 'Backup postponed',
            message: 'Low battery warning declined. Connect a charger and try again.',
          },
        },
      });
      navigate_without_exit_prompt(() => {
        router.replace('/error');
      });
    },
    choose_remove_after_backup: async (enabled: boolean) => {
      await preflight_service.set_remove_after_backup_enabled(enabled);
      const refreshed = await preflight_service.load_permission_summary();
      set_summary(refreshed);
      await apply_backup_command({ type: 'preflightResolved', result: { kind: 'success' } });
      navigate_without_exit_prompt(() => {
        router.replace('/transfer');
      });
    },
    return_home: () => {
      Alert.alert(
        'Leave backup setup?',
        'This will stop preflight and return to the backup home screen.',
        [
          { text: 'Keep Setting Up', style: 'cancel' },
          {
            text: 'Leave Setup',
            style: 'destructive',
            onPress: () => {
              void returnHome().then(() => {
                navigate_without_exit_prompt(() => {
                  router.replace('/');
                });
              });
            },
          },
        ]
      );
    },
  };
}
