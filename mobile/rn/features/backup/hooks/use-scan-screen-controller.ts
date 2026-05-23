import { useRouter } from 'expo-router';

export interface ScanScreenController {
  continue_to_pairing: () => void;
  return_home: () => void;
}

export function useScanScreenController(): ScanScreenController {
  const router = useRouter();
  return {
    continue_to_pairing: () => router.push('/pair'),
    return_home: () => router.push('/'),
  };
}
