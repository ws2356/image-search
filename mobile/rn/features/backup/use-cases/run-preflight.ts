import { PreflightFailureReason } from '@/features/backup/preflight/enums';
import type { PreflightResult } from '@/features/backup/preflight/models';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';
import type { BatteryStatusGateway } from '@/infrastructure/system/battery-status-gateway';
import type { PermissionGateway } from '@/infrastructure/system/permission-gateway';

export interface RunPreflightDeps {
  apply_command: typeof apply_backup_command;
  permission_gateway: PermissionGateway;
  battery_status_gateway: BatteryStatusGateway;
}

function resolve_preflight_result(permission_scope: 'full' | 'limited' | 'denied'): PreflightResult {
  if (permission_scope !== 'denied') {
    return { kind: 'success' };
  }
  return {
    kind: 'failure',
    reason: PreflightFailureReason.MissingMediaAccess,
    error: {
      title: 'Media permission required',
      message: 'Grant media permission to continue backup.',
    },
  };
}

export async function runPreflight(
  deps: RunPreflightDeps = {
    apply_command: apply_backup_command,
    permission_gateway: { get_media_permission_scope: async () => 'full' },
    battery_status_gateway: { get_current_snapshot: async () => ({ percentage: null, charging: null }) },
  }
): Promise<PreflightResult> {
  await deps.apply_command({ type: 'runPreflight' });
  const permission_scope = await deps.permission_gateway.get_media_permission_scope();
  await deps.battery_status_gateway.get_current_snapshot();
  const result = resolve_preflight_result(permission_scope);
  await deps.apply_command({ type: 'preflightResolved', result });
  return result;
}
