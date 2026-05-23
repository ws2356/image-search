import type { BackupRoutePhase } from '@/features/backup/domain/route-phase';
import { PermissionScope } from '@/features/backup/preflight/enums';
import type { PermissionSummary } from '@/features/backup/preflight/models';
import type {
  PairingSessionSummary,
  TrustedDesktopSummary,
} from '@/features/backup/pairing/models';
import type { ErrorSummary } from '@/features/backup/shared/models';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';

export interface HomeSummary {
  desktopName: string | null;
  lastBackupDescription: string | null;
  permissionScope: PermissionScope;
  interruptionWarning: string | null;
}

export interface LocalDeviceIdentitySummary {
  deviceUuid: string;
  deviceName: string;
  platform: 'android' | 'ios';
  updatedAt: string;
}

export interface BackupSessionState {
  routePhase: BackupRoutePhase;
  homeSummary: HomeSummary;
  permissionSummary: PermissionSummary;
  pairingSession: PairingSessionSummary | null;
  trustedDesktop: TrustedDesktopSummary | null;
  localDeviceIdentity: LocalDeviceIdentitySummary | null;
  transferSnapshot: TransferProgressSnapshot | null;
  latestError: ErrorSummary | null;
}

export const DEFAULT_HOME_SUMMARY: HomeSummary = {
  desktopName: null,
  lastBackupDescription: null,
  permissionScope: PermissionScope.Full,
  interruptionWarning: null,
};
