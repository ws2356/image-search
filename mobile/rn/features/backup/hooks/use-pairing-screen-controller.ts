import { useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Platform } from 'react-native';

import { DefaultPairingKeyDeriver } from '@/infrastructure/crypto/pairing-key-deriver';
import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { useBackupExitGuard } from '@/features/backup/hooks/use-backup-exit-guard';
import { PairingService } from '@/features/backup/services/pairing-service';
import { decode_pairing_link } from '@/features/backup/services/pairing-link-decoder';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import type { LocalDeviceIdentitySummary } from '@/features/backup/session/models';
import { returnHome } from '@/features/backup/use-cases/return-home';

const PAIRING_MISMATCH_TIMEOUT_MS = 15 * 60 * 1000;

export interface PairingScreenController {
  pairing_status_label: string;
  live_pairing_enabled: boolean;
  continue_to_permissions: () => void;
  return_home: () => void;
}

export function usePairingScreenController(): PairingScreenController {
  const router = useRouter();
  const params = useLocalSearchParams<{
    qr_payload?: string;
  }>();
  const qr_payload = typeof params.qr_payload === 'string' ? params.qr_payload.trim() : '';
  const [pairing_status_label, set_pairing_status_label] = useState(
    'Validating the QR payload and preparing a secure session.'
  );
  const live_pairing_enabled = qr_payload.length > 0;
  const navigate_without_exit_prompt = useBackupExitGuard(() => {
    Alert.alert(
      'Cancel pairing?',
      'This will stop waiting for the desktop and return to the backup home screen.',
      [
        { text: 'Keep Pairing', style: 'cancel' },
        {
          text: 'Cancel Pairing',
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

  const resolve_identity = useCallback(() => {
    const store = useBackupSessionStore.getState();
    const current_identity = store.session.localDeviceIdentity;
    if (current_identity) {
      return current_identity;
    }

    const platform: LocalDeviceIdentitySummary['platform'] = Platform.OS === 'ios' ? 'ios' : 'android';
    const new_identity: LocalDeviceIdentitySummary = {
      deviceUuid: `mobile-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}`,
      deviceName: 'AuBackup RN',
      platform,
      updatedAt: new Date().toISOString(),
    };
    store.setLocalDeviceIdentity(new_identity);
    return new_identity;
  }, []);

  useEffect(() => {
    if (!live_pairing_enabled) {
      return;
    }

    let cancelled = false;
    let has_finished = false;
    let poll_timer: ReturnType<typeof setInterval> | null = null;
    let mismatch_started_at_ms: number | null = null;

    const finish = () => {
      has_finished = true;
      if (poll_timer) {
        clearInterval(poll_timer);
        poll_timer = null;
      }
    };

    const fail_pairing = async (message: string) => {
      if (cancelled || has_finished) {
        return;
      }
      finish();
      set_pairing_status_label(message);
      await apply_backup_command({
        type: 'pairingFailed',
        error: {
          title: 'Pairing failed',
          message,
        },
      });
      if (!cancelled) {
        navigate_without_exit_prompt(() => {
          router.replace('/error');
        });
      }
    };

    const complete_pairing = async (
      response_session_id: string | null | undefined,
      response_desktop_name: string | null | undefined,
      endpoint_base_url: string,
      fallback_session_id: string,
      trust_key_b64: string
    ) => {
      if (cancelled || has_finished) {
        return;
      }
      finish();
      await apply_backup_command({
        type: 'pairingCompleted',
        session: {
          sessionId: response_session_id ?? fallback_session_id,
          desktopName: response_desktop_name ?? null,
          endpointBaseUrl: endpoint_base_url,
          pairingCompletedAt: new Date().toISOString(),
          trustKeyB64: trust_key_b64,
        },
      });
      if (!cancelled) {
        navigate_without_exit_prompt(() => {
          router.replace('/permissions');
        });
      }
    };

    const is_pairing_failure_state = (backup_state: string) =>
      backup_state === 'pairing_expired'
      || backup_state === 'pairing_stopped';

    const run_pairing = async () => {
      set_pairing_status_label('Validating QR payload…');
      const decoded = decode_pairing_link(qr_payload);
      if (!decoded.ok) {
        await fail_pairing(decoded.message);
        return;
      }

      const payload: PairingQRCodePayload = decoded.payload;
      const endpoint_target = payload.endpointTargets[0];
      if (!endpoint_target) {
        await fail_pairing('Pairing QR did not include a desktop endpoint.');
        return;
      }
      const endpoint_base_url =
        endpoint_target.startsWith('http://') || endpoint_target.startsWith('https://')
          ? endpoint_target
          : `http://${endpoint_target}`;

      const identity = resolve_identity();
      const pairing_key_deriver = new DefaultPairingKeyDeriver();
      const trust_key_b64 = await pairing_key_deriver.derive_pairing_key_b64({
        session_id: payload.sessionId,
        one_time_passcode: payload.oneTimePasscode,
        platform: identity.platform,
      });
      if (cancelled || has_finished) {
        return;
      }

      const pairing_service = new PairingService(endpoint_base_url);
      const session_id = payload.sessionId;

      const handle_response = async (response: Awaited<ReturnType<PairingService['get_pairing_state']>>) => {
        if (cancelled || has_finished) {
          return true;
        }
        if (response.backup_state !== 'pairing_mismatched') {
          mismatch_started_at_ms = null;
        }

        if (response.backup_state === 'pairing_mismatched') {
          if (mismatch_started_at_ms == null) {
            mismatch_started_at_ms = Date.now();
          }
          const elapsed_ms = Date.now() - mismatch_started_at_ms;
          if (elapsed_ms >= PAIRING_MISMATCH_TIMEOUT_MS) {
            await fail_pairing(
              'Pairing mismatch was not resolved on desktop within 15 minutes. Please restart pairing.'
            );
            return true;
          }
          set_pairing_status_label(
            response.message
            || 'Pairing mismatch detected on desktop. Waiting for desktop to resolve mismatch…'
          );
          return false;
        }

        set_pairing_status_label(response.message || `Pairing status: ${response.backup_state}`);
        if (response.backup_state === 'pairing_completed') {
          await complete_pairing(
            response.session_id,
            response.desktop_name,
            endpoint_base_url,
            session_id,
            trust_key_b64
          );
          return true;
        }
        if (is_pairing_failure_state(response.backup_state)) {
          await fail_pairing(response.message || `Pairing failed with state ${response.backup_state}.`);
          return true;
        }
        return false;
      };

      try {
        set_pairing_status_label('Reaching desktop…');
        const claim_response = await pairing_service.claim_pairing(payload, {
          device_uuid: identity.deviceUuid,
          device_name: identity.deviceName,
          platform: identity.platform,
        });
        if (await handle_response(claim_response)) {
          return;
        }
      } catch (claim_error) {
        const message = claim_error instanceof Error ? claim_error.message : 'Pairing request failed.';
        await fail_pairing(message);
        return;
      }

      set_pairing_status_label('Desktop reached. Verifying trust material…');
      const poll = async () => {
        if (cancelled || has_finished) {
          return;
        }
        try {
          const response = await pairing_service.get_pairing_state(session_id, identity.deviceUuid);
          const done = await handle_response(response);
          if (done) {
            finish();
          }
        } catch (poll_error) {
          const message = poll_error instanceof Error ? poll_error.message : 'Pairing state polling failed.';
          await fail_pairing(message);
        }
      };

      void poll();
      poll_timer = setInterval(() => {
        void poll();
      }, 2000);
    };

    void run_pairing().catch(async (error) => {
      const message = error instanceof Error ? error.message : 'Pairing request failed.';
      await fail_pairing(message);
    });

    return () => {
      cancelled = true;
      finish();
    };
  }, [live_pairing_enabled, navigate_without_exit_prompt, qr_payload, resolve_identity, router]);

  return {
    pairing_status_label,
    live_pairing_enabled,
    continue_to_permissions: () => router.push('/permissions'),
    return_home: () => {
      Alert.alert(
        'Cancel pairing?',
        'This will stop waiting for the desktop and return to the backup home screen.',
        [
          { text: 'Keep Pairing', style: 'cancel' },
          {
            text: 'Cancel Pairing',
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
