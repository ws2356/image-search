import type {
  PairingQRCodePayload,
  PairingSessionSummary,
} from '@/features/backup/pairing/models';
import type { PreflightResult } from '@/features/backup/preflight/models';
import type { ErrorSummary } from '@/features/backup/shared/models';
import type {
  TransferProgressSnapshot,
  TransferResult,
} from '@/features/backup/transfer/models';

export type BackupCommand =
  | { type: 'openScanFlow' }
  | { type: 'submitPairingPayload'; payload: PairingQRCodePayload }
  | { type: 'pairingCompleted'; session: PairingSessionSummary }
  | { type: 'pairingFailed'; error: ErrorSummary }
  | { type: 'runPreflight' }
  | { type: 'preflightResolved'; result: PreflightResult }
  | { type: 'startTransfer' }
  | { type: 'transferSnapshotUpdated'; snapshot: TransferProgressSnapshot }
  | { type: 'transferResolved'; result: TransferResult }
  | { type: 'stopTransfer' }
  | { type: 'completeTransfer' }
  | { type: 'recoverFromError' }
  | { type: 'returnHome' };
