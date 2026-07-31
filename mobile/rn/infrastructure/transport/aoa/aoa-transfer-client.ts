import {
  MOBILE_TRANSFER_SCHEMA,
  type TransferAssetExistenceRequest,
  type TransferAssetMetadata,
  type TransferCompleteRequest,
  type TransferResponse,
  type TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { NoopPayloadCipher, TransferPayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import type { PayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { AoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';

const MOBILE_TRANSPORT_SCHEMA = 'dtis.mobile-transport.v1';

export interface AoaTransferClientDeps {
  payload_cipher: PayloadCipher;
  trust_proof_signer: TrustProofSigner;
}

export class AoaTransferClient implements TransferClient {
  private readonly bridge: AoaBridge;
  private readonly context: TransferServiceContext;
  private readonly deps: AoaTransferClientDeps;

  constructor(bridge: AoaBridge, context: TransferServiceContext, deps?: Partial<AoaTransferClientDeps>) {
    this.bridge = bridge;
    this.context = context;
    this.deps = {
      payload_cipher:
        deps?.payload_cipher ??
        (context.encryption_enabled ? new TransferPayloadCipher(context.trust_key_b64) : new NoopPayloadCipher()),
      trust_proof_signer: deps?.trust_proof_signer ?? new DefaultTrustProofSigner(),
    };
  }

  async start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.start', body);
    return this.parse_response(response);
  }

  async existence(
    request: Omit<TransferAssetExistenceRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.existence', body);
    return this.parse_response(response);
  }

  async asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    if (stream_state === 'start') {
      const encrypted = await this.deps.payload_cipher.encrypt_json_payload(metadata);
      const body = { ...encrypted, stream_state, request_id, chunk_size: 256 * 1024 };
      const streaming_request_id = await this.bridge.beginStreamingRequest(
        JSON.stringify(this.envelope('transfer.asset', body, request_id))
      );
      return {
        schema: MOBILE_TRANSFER_SCHEMA,
        status: 'accepted',
        message: 'streaming started',
        request_id: streaming_request_id,
      };
    }
    if (stream_state === 'chunk') {
      if (!content) throw new Error('AOA asset chunk requires content');
      const encrypted = await this.deps.payload_cipher.encrypt_binary_chunk(content);
      await this.bridge.sendBinaryChunk(request_id, encrypted);
      return { schema: MOBILE_TRANSFER_SCHEMA, status: 'accepted', message: 'chunk accepted', request_id };
    }
    const response = await this.bridge.finishStreamingRequest(request_id);
    return this.parse_response(response);
  }

  async complete(
    request: Omit<TransferCompleteRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    abort_signal?.throwIfAborted();
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.complete', body);
    return this.parse_response(response);
  }

  private async send_request(operation: string, body: object): Promise<string> {
    const request_id = this.generate_request_id();
    const envelope = this.envelope(operation, body, request_id);
    return this.bridge.sendRequest(JSON.stringify(envelope));
  }

  private envelope(operation: string, body: object, request_id: string) {
    return {
      schema: MOBILE_TRANSPORT_SCHEMA,
      operation,
      request_id,
      body_schema: MOBILE_TRANSFER_SCHEMA,
      body,
    };
  }

  private parse_response(raw: string): TransferResponse {
    const parsed = JSON.parse(raw);
    if (parsed.body && typeof parsed.body === 'object') {
      return parsed.body as TransferResponse;
    }
    return parsed as TransferResponse;
  }

  private generate_request_id(): string {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}
