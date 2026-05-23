import { useRouter } from 'expo-router';

export interface PairingScreenController {
  continue_to_permissions: () => void;
  return_home: () => void;
}

export function usePairingScreenController(): PairingScreenController {
  const router = useRouter();
  return {
    continue_to_permissions: () => router.push('/permissions'),
    return_home: () => router.push('/'),
  };
}
