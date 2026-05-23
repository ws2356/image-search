import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';

import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { PairingService } from '@/features/backup/services/pairing-service';

export interface PairingScreenController {
  pairing_status_label: string;
  live_pairing_enabled: boolean;
  continue_to_permissions: () => void;
  return_home: () => void;
}

export function usePairingScreenController(): PairingScreenController {
  const router = useRouter();
  const orchestrator = useMemo(() => createBackupFlowOrchestrator(), []);
  const params = useLocalSearchParams<{
    session_id?: string;
    device_uuid?: string;
    endpoint_base_url?: string;
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
    const pairing_service = new PairingService(endpoint_base_url);
    let cancelled = false;

    const poll = async () => {
      try {
        const response = await pairing_service.get_pairing_state(session_id, device_uuid);
        if (cancelled) {
          return;
        }
        set_pairing_status_label(response.message || `Pairing status: ${response.status}`);
        switch (response.status) {
          case 'accepted':
            await orchestrator.execute({
              type: 'pairingCompleted',
              session: {
                sessionId: response.session_id ?? session_id,
                desktopName: response.device_name ?? null,
                endpointBaseUrl: endpoint_base_url,
                pairingCompletedAt: new Date().toISOString(),
              },
            });
            router.replace('/permissions');
            return;
          case 'rejected':
          case 'expired':
          case 'pairing_mismatched':
          case 'pairing_stopped':
            await orchestrator.execute({
              type: 'pairingFailed',
              error: {
                title: 'Pairing failed',
                message: response.message || `Pairing failed with status ${response.status}.`,
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
    orchestrator,
    params.device_uuid,
    params.endpoint_base_url,
    params.session_id,
    router,
  ]);

  return {
    pairing_status_label,
    live_pairing_enabled,
    continue_to_permissions: () => router.push('/permissions'),
    return_home: () => router.push('/'),
  };
}
