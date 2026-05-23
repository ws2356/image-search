import { useRouter } from 'expo-router';

export interface CompletionScreenController {
  return_home: () => void;
}

export function useCompletionScreenController(): CompletionScreenController {
  const router = useRouter();
  return {
    return_home: () => router.push('/'),
  };
}
