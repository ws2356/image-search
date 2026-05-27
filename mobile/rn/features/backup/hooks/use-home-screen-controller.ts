import { useRouter } from 'expo-router';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { PermissionScope } from '@/features/backup/preflight/enums';

export interface HomeScreenController {
  desktop_name: string | null;
  last_backup_description: string | null;
  permission_scope: PermissionScope;
  interruption_warning: string | null;
  has_session_history: boolean;
  start_backup: () => void;
}

export function useHomeScreenController(): HomeScreenController {
  const router = useRouter();
  const home_summary = useBackupSessionStore((state) => state.session.homeSummary);
  const permission_summary = useBackupSessionStore((state) => state.session.permissionSummary);
  const trusted_desktop = useBackupSessionStore((state) => state.session.trustedDesktop);
  const pairing_session = useBackupSessionStore((state) => state.session.pairingSession);

  const desktop_name =
    trusted_desktop?.desktopName ?? pairing_session?.desktopName ?? home_summary.desktopName;
  const last_backup_description = home_summary.lastBackupDescription;
  const permission_scope = permission_summary.mediaScope;
  const interruption_warning = home_summary.interruptionWarning;
  const has_session_history = desktop_name != null || last_backup_description != null;

  return {
    desktop_name,
    last_backup_description,
    permission_scope,
    interruption_warning,
    has_session_history,
    start_backup: () => router.replace('/scan'),
  };
}
