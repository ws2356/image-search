import { useRouter } from 'expo-router';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { returnHome } from '@/features/backup/use-cases/return-home';

export interface CompletionScreenController {
  items_backed_up: number | null;
  duration_description: string | null;
  return_home: () => void;
}

export function useCompletionScreenController(): CompletionScreenController {
  const router = useRouter();
  const transfer_snapshot = useBackupSessionStore((state) => state.session.transferSnapshot);

  const items_backed_up = transfer_snapshot?.counts.transferredAssets ?? null;
  return {
    items_backed_up,
    duration_description: null,
    return_home: () => {
      void returnHome().then(() => router.push('/'));
    },
  };
}
