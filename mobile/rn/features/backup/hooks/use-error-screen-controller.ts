import { useRouter } from 'expo-router';

export interface ErrorScreenController {
  retry_scan: () => void;
  return_home: () => void;
}

export function useErrorScreenController(): ErrorScreenController {
  const router = useRouter();
  return {
    retry_scan: () => router.push('/scan'),
    return_home: () => router.push('/'),
  };
}
