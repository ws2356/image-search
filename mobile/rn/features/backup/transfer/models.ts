import {
  TransferFailureReason,
  TransferPipelineStage,
  TransferTransport,
} from '@/features/backup/transfer/enums';
import type { ErrorSummary } from '@/features/backup/shared/models';

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
