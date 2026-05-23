import type { BackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { createBackupFlowOrchestrator } from '@/features/backup/orchestration/backup-flow-orchestrator';
import { PreflightFailureReason } from '@/features/backup/preflight/enums';
import type { PreflightResult } from '@/features/backup/preflight/models';
import type { BatteryStatusGateway } from '@/infrastructure/system/battery-status-gateway';
import type { PermissionGateway } from '@/infrastructure/system/permission-gateway';

export interface RunPreflightDeps {
  orchestrator: BackupFlowOrchestrator;
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
    orchestrator: createBackupFlowOrchestrator(),
    permission_gateway: { get_media_permission_scope: async () => 'full' },
    battery_status_gateway: { get_current_snapshot: async () => ({ percentage: null, charging: null }) },
  }
): Promise<PreflightResult> {
  await deps.orchestrator.runPreflight();
  const permission_scope = await deps.permission_gateway.get_media_permission_scope();
  await deps.battery_status_gateway.get_current_snapshot();
  const result = resolve_preflight_result(permission_scope);
  await deps.orchestrator.execute({ type: 'preflightResolved', result });
  return result;
}
