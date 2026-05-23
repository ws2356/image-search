import { useRouter } from 'expo-router';

export interface HomeScreenController {
  start_backup: () => void;
  go_pair: () => void;
  go_permissions: () => void;
  go_transfer: () => void;
}

export function useHomeScreenController(): HomeScreenController {
  const router = useRouter();
  return {
    start_backup: () => router.push('/scan'),
    go_pair: () => router.push('/pair'),
    go_permissions: () => router.push('/permissions'),
    go_transfer: () => router.push('/transfer'),
  };
}
