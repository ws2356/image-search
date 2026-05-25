import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Platform } from 'react-native';

import { DefaultPairingKeyDeriver } from '@/infrastructure/crypto/pairing-key-deriver';
import { PairingService } from '@/features/backup/services/pairing-service';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';

export interface PairingScreenController {
  pairing_status_label: string;
  live_pairing_enabled: boolean;
  continue_to_permissions: () => void;
  return_home: () => void;
}

export function usePairingScreenController(): PairingScreenController {
  const router = useRouter();
  const params = useLocalSearchParams<{
    session_id?: string;
    device_uuid?: string;
    endpoint_base_url?: string;
    one_time_passcode?: string;
    trust_key_b64?: string;
  }>();
  const [pairing_status_label, set_pairing_status_label] = useState(
    'Pairing session awaiting network state updates.'
  );
  const live_pairing_enabled = Boolean(params.session_id && params.device_uuid && params.endpoint_base_url);

  useEffect(() => {
    if (!live_pairing_enabled) {
      return;
    }

    const session_id = params.session_id as string;
    const device_uuid = params.device_uuid as string;
    const endpoint_base_url = params.endpoint_base_url as string;
    const one_time_passcode = params.one_time_passcode as string | undefined;
    const resolve_trust_key_b64 = async () => {
      const provided_trust_key = params.trust_key_b64 as string | undefined;
      if (provided_trust_key && provided_trust_key.length > 0) {
        return provided_trust_key;
      }
      if (!one_time_passcode) {
        return null;
      }

      const platform = useBackupSessionStore.getState().session.localDeviceIdentity?.platform
        ?? (Platform.OS === 'ios' ? 'ios' : 'android');
      const pairing_key_deriver = new DefaultPairingKeyDeriver();
      return pairing_key_deriver.derive_pairing_key_b64({
        session_id,
        one_time_passcode,
        platform,
      });
    };
    const pairing_service = new PairingService(endpoint_base_url);
    let cancelled = false;

    const poll = async () => {
      try {
        const response = await pairing_service.get_pairing_state(session_id, device_uuid);
        if (cancelled) {
          return;
        }
        console.log('[Pair] poll response', { backup_state: response.backup_state });
        set_pairing_status_label(response.message || `Pairing status: ${response.backup_state}`);
        switch (response.backup_state) {
          case 'pairing_completed':
            const trustKeyB64 = await resolve_trust_key_b64();
            if (cancelled) {
              return;
            }
            if (!trustKeyB64) {
              set_pairing_status_label('Pairing completed, but trust key derivation failed.');
              return;
            }
            console.log('[Pair] pairing_completed — applying command and navigating to /permissions');
            await apply_backup_command({
              type: 'pairingCompleted',
              session: {
                sessionId: response.session_id ?? session_id,
                desktopName: response.desktop_name ?? null,
                endpointBaseUrl: endpoint_base_url,
                pairingCompletedAt: new Date().toISOString(),
                trustKeyB64,
              },
            });
            router.replace('/permissions');
            return;
          case 'pairing_expired':
          case 'pairing_mismatched':
          case 'pairing_stopped':
            await apply_backup_command({
              type: 'pairingFailed',
              error: {
                title: 'Pairing failed',
                message: response.message || `Pairing failed with state ${response.backup_state}.`,
              },
            });
            router.replace('/error');
            return;
          default:
            return;
        }
      } catch (poll_error) {
        if (cancelled) {
          return;
        }
        const message = poll_error instanceof Error ? poll_error.message : 'Pairing state polling failed.';
        console.log('[Pair] poll error', message);
        set_pairing_status_label(message);
      }
    };

    void poll();
    const interval = setInterval(() => {
      void poll();
    }, 2000);

    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [
    live_pairing_enabled,
    params.device_uuid,
    params.endpoint_base_url,
    params.session_id,
    params.one_time_passcode,
    params.trust_key_b64,
    router,
  ]);

  return {
    pairing_status_label,
    live_pairing_enabled,
    continue_to_permissions: () => router.push('/permissions'),
    return_home: () => router.push('/'),
  };
}
