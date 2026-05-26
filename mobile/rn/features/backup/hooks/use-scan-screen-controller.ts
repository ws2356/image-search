import { useRouter } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { ExpoCameraQrScannerPort } from '@/infrastructure/system/qr-scanner-port';

export interface ScanScreenController {
  camera_permission_granted: boolean;
  camera_permission_can_ask_again: boolean;
  request_camera_permission: () => Promise<void>;
  handle_barcode_scanned: (data: string) => void;
  return_home: () => void;
}

export function useScanScreenController(): ScanScreenController {
  const router = useRouter();
  const qr_scanner_port = useMemo(() => new ExpoCameraQrScannerPort(), []);
  const [camera_permission_granted, set_camera_permission_granted] = useState(false);
  const [camera_permission_can_ask_again, set_camera_permission_can_ask_again] = useState(true);
  const has_navigated_ref = useRef(false);

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

  const handle_barcode_scanned = useCallback((data: string) => {
    if (has_navigated_ref.current) {
      return;
    }
    const qr_payload = data.trim();
    if (!qr_payload) {
      return;
    }
    has_navigated_ref.current = true;
    router.push({
      pathname: '/pair',
      params: {
        qr_payload,
      },
    });
  }, [router]);

  return {
    camera_permission_granted,
    camera_permission_can_ask_again,
    request_camera_permission: async () => {
      const snapshot = await qr_scanner_port.request_permission();
      set_camera_permission_granted(snapshot.granted);
      set_camera_permission_can_ask_again(snapshot.canAskAgain);
    },
    handle_barcode_scanned,
    return_home: () => router.push('/'),
  };
}
