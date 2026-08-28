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
  /**
   * True when an error indicates the transport link itself dropped (rather than
   * a genuine asset rejection). Transports that can resync (AOA) retry such
   * errors; others default to false.
   */
  is_connection_error?(error: unknown): boolean;
  /**
   * Waits up to timeout_ms for the transport to re-establish after a connection
   * drop. Returns true if the link is usable again, false on timeout. Transports
   * without a resync concept resolve immediately.
   */
  wait_for_reconnection?(timeout_ms: number): Promise<boolean>;
}
