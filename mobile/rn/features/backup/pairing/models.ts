import { PairingFailureReason } from '@/features/backup/pairing/enums';
import type { ErrorSummary } from '@/features/backup/shared/models';

export interface PairingQRCodePayload {
  schemaVersion: number;
  endpointTargets: string[];
  sessionId: string;
  oneTimePasscode: string;
  suggestedUsbPort?: number;
  strictSecurityEnabled: boolean;
}

export interface PairingSessionSummary {
  sessionId: string | null;
  desktopName: string | null;
  endpointBaseUrl: string | null;
  pairingCompletedAt: string | null;
  trustKeyB64: string | null;
}

export interface TrustedDesktopSummary {
  desktopId: string;
  desktopName: string;
  claimedAt: string;
  endpointBaseUrls: string[];
  lastSuccessfulSessionId: string | null;
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
