import { useRouter } from 'expo-router';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { returnHome } from '@/features/backup/use-cases/return-home';

export interface CompletionScreenController {
  items_backed_up: number | null;
  duration_description: string | null;
  return_home: () => void;
}

function format_duration_description(started_at: string, last_updated_at: string): string | null {
  const started_at_ms = Date.parse(started_at);
  const last_updated_at_ms = Date.parse(last_updated_at);
  if (Number.isNaN(started_at_ms) || Number.isNaN(last_updated_at_ms) || last_updated_at_ms < started_at_ms) {
    return null;
  }
  const total_seconds = Math.max(1, Math.round((last_updated_at_ms - started_at_ms) / 1000));
  if (total_seconds < 60) {
    return `${total_seconds} sec`;
  }
  const total_minutes = Math.floor(total_seconds / 60);
  if (total_minutes < 60) {
    return `${total_minutes} min`;
  }
  const hours = Math.floor(total_minutes / 60);
  const minutes = total_minutes % 60;
  return minutes === 0 ? `${hours} hr` : `${hours} hr ${minutes} min`;
}

export function useCompletionScreenController(): CompletionScreenController {
  const router = useRouter();
  const transfer_snapshot = useBackupSessionStore((state) => state.session.transferSnapshot);

  const items_backed_up = transfer_snapshot?.counts.transferredAssets ?? null;
  const duration_description =
    transfer_snapshot != null
      ? format_duration_description(transfer_snapshot.startedAt, transfer_snapshot.lastUpdatedAt)
      : null;

  return {
    items_backed_up,
    duration_description,
    return_home: () => {
      void returnHome().then(() => router.replace('/'));
    },
  };
}
