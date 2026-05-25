import { useRouter } from 'expo-router';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { returnHome } from '@/features/backup/use-cases/return-home';

export interface CompletionScreenController {
  items_backed_up: number | null;
  completed_at_description: string | null;
  return_home: () => void;
}

export function useCompletionScreenController(): CompletionScreenController {
  const router = useRouter();
  const transfer_snapshot = useBackupSessionStore((state) => state.session.transferSnapshot);

  const items_backed_up = transfer_snapshot?.counts.transferredAssets ?? null;
  const completed_at = transfer_snapshot?.lastUpdatedAt ?? null;
  const completed_at_description = completed_at
    ? new Date(completed_at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
    : null;

  return {
    items_backed_up,
    completed_at_description,
    return_home: () => {
      void returnHome().then(() => router.push('/'));
    },
  };
}
