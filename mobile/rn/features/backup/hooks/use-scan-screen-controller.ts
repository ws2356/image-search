import { useRouter } from 'expo-router';
import { Platform } from 'react-native';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { PairingService } from '@/features/backup/services/pairing-service';
import { decode_pairing_link } from '@/features/backup/services/pairing-link-decoder';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import type { LocalDeviceIdentitySummary } from '@/features/backup/session/models';
import { DefaultPairingKeyDeriver } from '@/infrastructure/crypto/pairing-key-deriver';
import { ExpoCameraQrScannerPort } from '@/infrastructure/system/qr-scanner-port';

export interface ScanScreenController {
  camera_permission_granted: boolean;
  camera_permission_can_ask_again: boolean;
  request_camera_permission: () => Promise<void>;
  is_claiming: boolean;
  scan_error: string | null;
  handle_barcode_scanned: (data: string) => Promise<void>;
  clear_scan_error: () => void;
  return_home: () => void;
}

export function useScanScreenController(): ScanScreenController {
  const router = useRouter();
  const qr_scanner_port = useMemo(() => new ExpoCameraQrScannerPort(), []);
  const [camera_permission_granted, set_camera_permission_granted] = useState(false);
  const [camera_permission_can_ask_again, set_camera_permission_can_ask_again] = useState(true);
  const [is_claiming, set_is_claiming] = useState(false);
  const is_claiming_ref = useRef(false);
  const [scan_error, set_scan_error] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const load_permission = async () => {
      const snapshot = await qr_scanner_port.get_permission_snapshot();
      if (!cancelled) {
        set_camera_permission_granted(snapshot.granted);
        set_camera_permission_can_ask_again(snapshot.canAskAgain);
      }
    };
    void load_permission();
    return () => {
      cancelled = true;
    };
  }, [qr_scanner_port]);

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

  const handle_barcode_scanned = useCallback(
    async (data: string) => {
      if (is_claiming_ref.current) {
        return;
      }
      is_claiming_ref.current = true;
      set_is_claiming(true);
      set_scan_error(null);

      try {
        const decoded = decode_pairing_link(data);
        if (!decoded.ok) {
          set_scan_error(decoded.message);
          return;
        }
        console.log('[Scan] Decoded QR', { sessionId: decoded.payload.sessionId, opt: decoded.payload.oneTimePasscode });

        const payload: PairingQRCodePayload = decoded.payload;
        const endpoint_target = payload.endpointTargets[0];
        if (!endpoint_target) {
          set_scan_error('Pairing QR did not include a desktop endpoint.');
          return;
        }

        const endpoint_base_url =
          endpoint_target.startsWith('http://') || endpoint_target.startsWith('https://')
            ? endpoint_target
            : `http://${endpoint_target}`;

        const identity = resolve_identity();
        console.log('[Scan] Starting pairing claim', { session_id: payload.sessionId, endpoint_base_url });
        const pairing_key_deriver = new DefaultPairingKeyDeriver();
        const trust_key_b64 = await pairing_key_deriver.derive_pairing_key_b64({
          session_id: payload.sessionId,
          one_time_passcode: payload.oneTimePasscode,
          platform: identity.platform,
        });
        const pairing_service = new PairingService(endpoint_base_url);

        const response = await pairing_service.claim_pairing(payload, {
          device_uuid: identity.deviceUuid,
          device_name: identity.deviceName,
          platform: identity.platform,
        });
        console.log('[Scan] claim_pairing response', { backup_state: response.backup_state, session_id: response.session_id });
        if (
          response.backup_state === 'pairing_mismatched' ||
          response.backup_state === 'pairing_stopped' ||
          response.backup_state === 'pairing_expired'
        ) {
          set_scan_error(response.message || `Pairing failed with state ${response.backup_state}.`);
          return;
        }

        router.push({
          pathname: '/pair',
          params: {
            session_id: response.session_id ?? payload.sessionId,
            device_uuid: response.device_uuid ?? identity.deviceUuid,
            endpoint_base_url,
            one_time_passcode: payload.oneTimePasscode,
            trust_key_b64,
          },
        });
        console.log('[Scan] Navigated to /pair');
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Pairing claim failed.';
        console.log('[Scan] claim_pairing error', message);
        set_scan_error(message);
      } finally {
        is_claiming_ref.current = false;
        set_is_claiming(false);
      }
    },
    [resolve_identity, router]
  );

  return {
    camera_permission_granted,
    camera_permission_can_ask_again,
    request_camera_permission: async () => {
      const snapshot = await qr_scanner_port.request_permission();
      set_camera_permission_granted(snapshot.granted);
      set_camera_permission_can_ask_again(snapshot.canAskAgain);
    },
    is_claiming,
    scan_error,
    handle_barcode_scanned,
    clear_scan_error: () => {
      set_scan_error(null);
      is_claiming_ref.current = false;
    },
    return_home: () => router.push('/'),
  };
}
