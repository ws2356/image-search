import {
  MOBILE_TRANSFER_SCHEMA,
  type TransferAssetExistenceRequest,
  type TransferAssetMetadata,
  type TransferCompleteRequest,
  type TransferResponse,
  type TransferSessionRequest,
} from '@/features/backup/protocols/transfer';

export interface LanTransferClient {
  start(request: TransferSessionRequest): Promise<TransferResponse>;
  existence(request: TransferAssetExistenceRequest): Promise<TransferResponse>;
  asset(
    metadata: TransferAssetMetadata,
    content: Uint8Array,
    stream_state: 'start' | 'chunk' | 'complete'
  ): Promise<TransferResponse>;
  complete(request: TransferCompleteRequest): Promise<TransferResponse>;
}

export class FakeLanTransferClient implements LanTransferClient {
  async start(request: TransferSessionRequest): Promise<TransferResponse> {
    return {
      schema: MOBILE_TRANSFER_SCHEMA,
      status: 'rejected',
      message: `LAN transfer start stub is not implemented yet for session_id=${request.session_id}.`,
      session_id: request.session_id,
      device_uuid: request.device_uuid,
    };
  }

  async existence(request: TransferAssetExistenceRequest): Promise<TransferResponse> {
    return {
      schema: MOBILE_TRANSFER_SCHEMA,
      status: 'checked',
      message: `LAN transfer existence stub returned no matches for session_id=${request.session_id}.`,
      session_id: request.session_id,
      device_uuid: request.device_uuid,
      matches: [],
    };
  }

  async asset(
    metadata: TransferAssetMetadata,
    _content: Uint8Array,
    _stream_state: 'start' | 'chunk' | 'complete'
  ): Promise<TransferResponse> {
    return {
      schema: MOBILE_TRANSFER_SCHEMA,
      status: 'rejected',
      message: `LAN transfer asset stub is not implemented yet for asset_id=${metadata.asset_id}.`,
      session_id: metadata.session_id,
      device_uuid: metadata.device_uuid,
    };
  }

  async complete(request: TransferCompleteRequest): Promise<TransferResponse> {
    return {
      schema: MOBILE_TRANSFER_SCHEMA,
      status: 'completed',
      message: `LAN transfer complete stub acknowledged session_id=${request.session_id}.`,
      session_id: request.session_id,
      device_uuid: request.device_uuid,
      transferred_count: request.transferred_count,
      failed_count: request.failed_count,
    };
  }
}
