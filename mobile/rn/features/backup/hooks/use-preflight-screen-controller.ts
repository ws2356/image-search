import { useRouter } from 'expo-router';

export interface PreflightScreenController {
  continue_to_transfer: () => void;
  return_home: () => void;
}

export function usePreflightScreenController(): PreflightScreenController {
  const router = useRouter();
  return {
    continue_to_transfer: () => router.push('/transfer'),
    return_home: () => router.push('/'),
  };
}
