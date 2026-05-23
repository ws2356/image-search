import { PermissionScope, PreflightFailureReason } from '@/features/backup/preflight/enums';
import type { ErrorSummary } from '@/features/backup/shared/models';

export interface PermissionSummary {
  mediaScope: PermissionScope;
  batteryPercentage: number | null;
  removeAfterBackupEnabled: boolean;
}

export interface PreflightResultSuccess {
  kind: 'success';
}

export interface PreflightResultFailure {
  kind: 'failure';
  reason: PreflightFailureReason;
  error: ErrorSummary;
}

export type PreflightResult = PreflightResultSuccess | PreflightResultFailure;

export const DEFAULT_PERMISSION_SUMMARY: PermissionSummary = {
  mediaScope: PermissionScope.Full,
  batteryPercentage: null,
  removeAfterBackupEnabled: false,
};
