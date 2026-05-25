import { create_default_preflight_service, type PreflightService } from '@/features/backup/services/preflight-service';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import type { PermissionSummary } from '@/features/backup/preflight/models';

export interface RunPreflightDeps {
  apply_command: typeof apply_backup_command;
  preflight_service: PreflightService;
}

export async function runPreflight(
  deps: RunPreflightDeps = {
    apply_command: apply_backup_command,
    preflight_service: create_default_preflight_service(),
  }
): Promise<PermissionSummary> {
  await deps.apply_command({ type: 'runPreflight' });
  const summary = await deps.preflight_service.load_permission_summary();
  useBackupSessionStore.getState().setPermissionSummary(summary);
  return summary;
}
