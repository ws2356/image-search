export const MOBILE_TRANSFER_SCHEMA = 'dtis.mobile-transfer.v1' as const;
export const MOBILE_TRANSFER_START_PATH = '/api/mobile/transfer/start' as const;
export const MOBILE_TRANSFER_EXISTENCE_PATH = '/api/mobile/transfer/existence' as const;
export const MOBILE_TRANSFER_ASSET_PATH = '/api/mobile/transfer/asset' as const;
export const MOBILE_TRANSFER_COMPLETE_PATH = '/api/mobile/transfer/complete' as const;

export const MOBILE_TRANSFER_START_PROOF_PURPOSE = 'transfer.start' as const;
export const MOBILE_TRANSFER_EXISTENCE_PROOF_PURPOSE = 'transfer.existence' as const;
export const MOBILE_TRANSFER_ASSET_PROOF_PURPOSE = 'transfer.asset' as const;
export const MOBILE_TRANSFER_COMPLETE_PROOF_PURPOSE = 'transfer.complete' as const;
export const MOBILE_TRANSFER_INTERRUPTION_REASON_STOPPED_BY_USER = 'stopped_by_user' as const;

export interface TransferSessionRequest {
  schema: typeof MOBILE_TRANSFER_SCHEMA;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  total_assets?: number;
  transferred_count?: number;
  failed_count?: number;
}

export interface TransferAssetSignature {
  asset_id: string;
  sha1: string;
  file_size: number;
  created_at: string;
}

export interface TransferAssetExistenceRequest {
  schema: typeof MOBILE_TRANSFER_SCHEMA;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  assets: TransferAssetSignature[];
}

export interface TransferAssetMetadata {
  schema: typeof MOBILE_TRANSFER_SCHEMA;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  asset_id: string;
  asset_version?: string;
  sha1?: string;
  file_size?: number;
  filename: string;
  media_type?: string;
  created_at?: string;
  updated_at?: string;
}

export type TransferAssetStreamState = 'start' | 'chunk' | 'complete';

export interface TransferCompleteRequest {
  schema: typeof MOBILE_TRANSFER_SCHEMA;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  transferred_count?: number;
  failed_count?: number;
  interruption_reason?: string;
}

export interface TransferMatchItem {
  asset_id: string;
  local_relative_path: string;
}

export interface TransferResponse {
  schema: typeof MOBILE_TRANSFER_SCHEMA;
  status: 'accepted' | 'checked' | 'stored' | 'skipped' | 'completed' | 'rejected';
  message: string;
  request_id?: string;
  session_id?: string;
  device_uuid?: string;
  total_assets?: number;
  matches?: TransferMatchItem[];
  transferred_count?: number;
  failed_count?: number;
  local_relative_path?: string;
  failure_code?: string;
}
