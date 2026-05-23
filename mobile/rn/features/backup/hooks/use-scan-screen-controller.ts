import { useRouter } from 'expo-router';

export interface ScanScreenController {
  continue_to_pairing: () => void;
  open_manual_payload_entry: () => void;
  return_home: () => void;
}

export function useScanScreenController(): ScanScreenController {
  const router = useRouter();
  return {
    continue_to_pairing: () => router.push('/pair'),
    open_manual_payload_entry: () => router.push('/manual-payload'),
    return_home: () => router.push('/'),
  };
}
