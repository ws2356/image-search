import type {
  TransferAssetExistenceRequest,
  TransferAssetMetadata,
  TransferCompleteRequest,
  TransferResponse,
  TransferSessionRequest,
} from '@/features/backup/protocols/transfer';

export interface TransferClient {
  start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
  existence(
    request: Omit<TransferAssetExistenceRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse>;
  asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse>;
  complete(request: Omit<TransferCompleteRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
}
