import { MOBILE_TRANSFER_SCHEMA } from '@/features/backup/protocols/transfer';
import type {
  TransferAssetExistenceRequest,
  TransferAssetMetadata,
  TransferAssetSignature,
  TransferCompleteRequest,
  TransferResponse,
  TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import { NoopPayloadCipher, TransferPayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import type { HttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';

export interface TransferServiceContext {
  endpoint_base_url: string;
  session_id: string;
  device_uuid: string;
  trust_key_b64: string;
  encryption_enabled?: boolean;
}

export interface TransferServiceDeps {
  transfer_client: HttpTransferClient;
  trust_proof_signer: TrustProofSigner;
}

export type TransferChunkUploadedCallback = (chunk_length: number) => Promise<void> | void;

export class TransferService {
  private readonly context: TransferServiceContext;
  private readonly deps: TransferServiceDeps;

  constructor(context: TransferServiceContext, deps?: Partial<TransferServiceDeps>) {
    this.context = context;
    const payload_cipher = context.encryption_enabled
      ? new TransferPayloadCipher(context.trust_key_b64)
      : new NoopPayloadCipher();
    this.deps = {
      transfer_client: deps?.transfer_client ?? new DefaultHttpTransferClient(context.endpoint_base_url, fetch, payload_cipher),
      trust_proof_signer: deps?.trust_proof_signer ?? new DefaultTrustProofSigner(),
    };
  }

  async start(total_assets: number, abort_signal?: AbortSignal): Promise<TransferResponse> {
    const trust_proof = await this.build_transfer_trust_proof('transfer.start');
    const request: Omit<TransferSessionRequest, 'schema'> = {
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      total_assets,
      transferred_count: 0,
      failed_count: 0,
    };
    return this.deps.transfer_client.start(request, abort_signal);
  }

  async check_existence(assets: TransferAssetSignature[], abort_signal?: AbortSignal): Promise<TransferResponse> {
    const trust_proof = await this.build_transfer_trust_proof('transfer.existence');
    const request: Omit<TransferAssetExistenceRequest, 'schema'> = {
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      assets,
    };
    return this.deps.transfer_client.existence(request, abort_signal);
  }

  async upload_asset(
    metadata: Omit<TransferAssetMetadata, 'schema' | 'session_id' | 'device_uuid' | 'trust_proof'>,
    content: Uint8Array
  ): Promise<TransferResponse> {
    return this.upload_asset_chunked(
      metadata,
      async (offset: number, length: number) => content.slice(offset, offset + length),
      content.length
    );
  }

  async upload_asset_chunked(
    metadata: Omit<TransferAssetMetadata, 'schema' | 'session_id' | 'device_uuid' | 'trust_proof'>,
    read_chunk: (offset: number, length: number) => Promise<Blob | Uint8Array>,
    total_size_bytes?: number,
    chunk_size_bytes = 256 * 1024,
    abort_signal?: AbortSignal,
    on_chunk_uploaded?: TransferChunkUploadedCallback
  ): Promise<TransferResponse> {
    const request_id = metadata.asset_id;
    const trust_proof = await this.build_transfer_trust_proof('transfer.asset');
    const full_metadata: TransferAssetMetadata = {
      schema: MOBILE_TRANSFER_SCHEMA,
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      ...metadata,
    };
    await this.deps.transfer_client.asset(full_metadata, request_id, 'start', undefined, abort_signal);

    let offset = 0;
    while (true) {
      if (abort_signal?.aborted) {
        throw new Error('Transfer stopped by user.');
      }
      if (typeof total_size_bytes === 'number' && total_size_bytes >= 0 && offset >= total_size_bytes) {
        break;
      }
      const remaining =
        typeof total_size_bytes === 'number' && total_size_bytes >= 0 ? total_size_bytes - offset : chunk_size_bytes;
      const next_length = Math.max(0, Math.min(chunk_size_bytes, remaining));
      const chunk = await read_chunk(offset, next_length);
      const chunk_length = chunk instanceof Uint8Array ? chunk.length : chunk.size;
      if (chunk_length === 0) {
        break;
      }
      await this.deps.transfer_client.asset(full_metadata, request_id, 'chunk', chunk, abort_signal);
      offset += chunk_length;
      if (on_chunk_uploaded) {
        await on_chunk_uploaded(chunk_length);
      }
    }
    if (abort_signal?.aborted) {
      throw new Error('Transfer stopped by user.');
    }
    return this.deps.transfer_client.asset(full_metadata, request_id, 'complete', undefined, abort_signal);
  }

  async complete(
    transferred_count: number,
    failed_count: number,
    abort_signal?: AbortSignal,
    interruption_reason?: string
  ): Promise<TransferResponse> {
    const trust_proof = await this.build_transfer_trust_proof('transfer.complete');
    const request: Omit<TransferCompleteRequest, 'schema'> = {
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      transferred_count,
      failed_count,
      interruption_reason,
    };
    return this.deps.transfer_client.complete(request, abort_signal);
  }

  private async build_transfer_trust_proof(
    purpose: 'transfer.start' | 'transfer.existence' | 'transfer.asset' | 'transfer.complete'
  ): Promise<string> {
    return this.deps.trust_proof_signer.derive_trust_proof({
      purpose,
      schema: MOBILE_TRANSFER_SCHEMA,
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_key_b64: this.context.trust_key_b64,
    });
  }
}
