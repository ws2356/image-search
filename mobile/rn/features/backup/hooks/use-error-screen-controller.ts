import { useRouter } from 'expo-router';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { returnHome } from '@/features/backup/use-cases/return-home';

export interface ErrorScreenController {
  error_title: string;
  error_message: string;
  retry_scan: () => void;
  return_home: () => void;
}

export function useErrorScreenController(): ErrorScreenController {
  const router = useRouter();
  const latest_error = useBackupSessionStore((state) => state.session.latestError);

  return {
    error_title: latest_error?.title ?? 'Something went wrong',
    error_message: latest_error?.message ?? 'An unexpected error occurred. You can try again or return home.',
    retry_scan: () => {
      void apply_backup_command({ type: 'recoverFromError' }).then(() => router.replace('/scan'));
    },
    return_home: () => {
      void returnHome().then(() => router.replace('/'));
    },
  };
}
