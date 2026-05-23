import type {
  ErrorSummary,
  PairingQRCodePayload,
  PairingSessionSummary,
  PreflightResult,
  TransferProgressSnapshot,
  TransferResult,
} from '@/src/features/backup/domain/models';

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
