import {
  PairingFailureReason,
  PermissionScope,
  PreflightFailureReason,
  TransferFailureReason,
  TransferPipelineStage,
  TransferTransport,
} from '@/features/backup/domain/enums';
import type { BackupRoutePhase } from '@/features/backup/domain/route-phase';

export interface ErrorSummary {
  title: string;
  message: string;
}

export interface PairingQRCodePayload {
  schemaVersion: number;
  endpointTargets: string[];
  sessionId: string;
  oneTimePasscode: string;
  suggestedUsbPort?: number;
  strictSecurityEnabled: boolean;
}

export interface HomeSummary {
  desktopName: string | null;
  lastBackupDescription: string | null;
  permissionScope: PermissionScope;
  interruptionWarning: string | null;
}

export interface PermissionSummary {
  mediaScope: PermissionScope;
  batteryPercentage: number | null;
  removeAfterBackupEnabled: boolean;
}

export interface PairingSessionSummary {
  sessionId: string | null;
  desktopName: string | null;
  endpointBaseUrl: string | null;
  pairingCompletedAt: string | null;
}

export interface TrustedDesktopSummary {
  desktopId: string;
  desktopName: string;
  claimedAt: string;
  endpointBaseUrls: string[];
  lastSuccessfulSessionId: string | null;
}

export interface LocalDeviceIdentitySummary {
  deviceUuid: string;
  deviceName: string;
  platform: 'android' | 'ios';
  updatedAt: string;
}

export interface TransferCountsSnapshot {
  totalAssets: number;
  matchedAssets: number;
  transferredAssets: number;
  failedAssets: number;
}

export interface TransferProgressSnapshot {
  pipelineStage: TransferPipelineStage;
  transport: TransferTransport;
  counts: TransferCountsSnapshot;
  activeAssetId: string | null;
  activeRequestId: string | null;
  bytesUploaded: number;
  bytesPerSecond: number | null;
  estimatedSecondsRemaining: number | null;
  lastUpdatedAt: string;
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

export interface PairingResultSuccess {
  kind: 'success';
  session: PairingSessionSummary;
}

export interface PairingResultFailure {
  kind: 'failure';
  reason: PairingFailureReason;
  error: ErrorSummary;
}

export type PairingResult = PairingResultSuccess | PairingResultFailure;

export interface PreflightResultSuccess {
  kind: 'success';
}

export interface PreflightResultFailure {
  kind: 'failure';
  reason: PreflightFailureReason;
  error: ErrorSummary;
}

export type PreflightResult = PreflightResultSuccess | PreflightResultFailure;

export interface TransferResultSuccess {
  kind: 'success';
  completedAt: string;
}

export interface TransferResultFailure {
  kind: 'failure';
  reason: TransferFailureReason;
  error: ErrorSummary;
}

export type TransferResult = TransferResultSuccess | TransferResultFailure;

export const DEFAULT_HOME_SUMMARY: HomeSummary = {
  desktopName: null,
  lastBackupDescription: null,
  permissionScope: PermissionScope.Full,
  interruptionWarning: null,
};

export const DEFAULT_PERMISSION_SUMMARY: PermissionSummary = {
  mediaScope: PermissionScope.Full,
  batteryPercentage: null,
  removeAfterBackupEnabled: false,
};
