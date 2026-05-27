import { DEFAULT_HOME_SUMMARY, type BackupSessionState, type HomeSummary } from '@/features/backup/session/models';

function format_backup_duration(started_at: string, last_updated_at: string): string | null {
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

export function build_last_backup_description(
  session: BackupSessionState,
  options: { prefix?: string } = {}
): string | null {
  const snapshot = session.transferSnapshot;
  if (!snapshot) {
    return null;
  }
  const item_count = snapshot.counts.transferredAssets;
  const item_label = item_count === 1 ? '1 item' : `${item_count} items`;
  const duration = format_backup_duration(snapshot.startedAt, snapshot.lastUpdatedAt);
  const base_description = duration ? `${item_label} in ${duration}` : item_label;
  return options.prefix ? `${options.prefix}${base_description}` : base_description;
}

export function build_home_summary_from_session(
  session: BackupSessionState,
  options: { interruption_warning: string | null; last_backup_prefix?: string } = {
    interruption_warning: null,
  }
): HomeSummary {
  return {
    ...DEFAULT_HOME_SUMMARY,
    desktopName: session.trustedDesktop?.desktopName ?? session.pairingSession?.desktopName ?? session.homeSummary.desktopName,
    lastBackupDescription: build_last_backup_description(session, {
      prefix: options.last_backup_prefix,
    }),
    permissionScope: session.permissionSummary.mediaScope,
    interruptionWarning: options.interruption_warning,
  };
}
