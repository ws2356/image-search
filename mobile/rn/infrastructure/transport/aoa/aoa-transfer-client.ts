import QuickCrypto from 'react-native-quick-crypto';
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
import { create_transfer_abort_error } from '@/features/backup/transfer/transfer-abort';

const MOBILE_TRANSPORT_SCHEMA = 'dtis.mobile-transport.v1';

const AOA_REQUEST_ID_LENGTH = 36;

/**
 * AOA frames carry a fixed 36-byte request id. Asset streaming uses the asset
 * content URI as its request id, which can exceed 36 bytes and would break the
 * frame codec. Derive a deterministic 36-byte id so the start envelope, binary
 * chunks, and completion envelope all share one id that the desktop can correlate.
 */
function to_aoa_stream_request_id(request_id: string): string {
  if (request_id.length > AOA_REQUEST_ID_LENGTH) {
    return QuickCrypto.createHash('sha1').update(request_id).digest('hex').slice(0, AOA_REQUEST_ID_LENGTH);
  }
  return request_id.padEnd(AOA_REQUEST_ID_LENGTH, ' ');
}

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

  /**
   * AbortSignal.throwIfAborted is not available in the Hermes runtime (it is
   * undefined), so relying on it would throw "undefined is not a function".
   * Check the always-present `aborted` flag instead.
   */
  private throw_if_transfer_aborted(abort_signal?: AbortSignal): void {
    if (abort_signal?.aborted) {
      throw create_transfer_abort_error();
    }
  }

  async start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    this.throw_if_transfer_aborted(abort_signal);
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    const response = await this.send_request('transfer.start', body);
    return this.parse_response(response);
  }
  async existence(
    request: Omit<TransferAssetExistenceRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    this.throw_if_transfer_aborted(abort_signal);
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
    this.throw_if_transfer_aborted(abort_signal);
    const stream_request_id = to_aoa_stream_request_id(request_id);
    if (stream_state === 'start') {
      const encrypted = await this.deps.payload_cipher.encrypt_json_payload(metadata);
      const body = { ...encrypted, stream_state, request_id: stream_request_id, chunk_size: 256 * 1024 };
      const streaming_request_id = await this.bridge.beginStreamingRequest(
        JSON.stringify(this.envelope('transfer.asset', body, stream_request_id))
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
      await this.bridge.sendBinaryChunk(stream_request_id, encrypted);
      return { schema: MOBILE_TRANSFER_SCHEMA, status: 'accepted', message: 'chunk accepted', request_id: stream_request_id };
    }
    const response = await this.bridge.finishStreamingRequest(stream_request_id);
    return this.parse_response(response);
  }

  async complete(
    request: Omit<TransferCompleteRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    this.throw_if_transfer_aborted(abort_signal);
    const body = { schema: MOBILE_TRANSFER_SCHEMA, ...request };
    console.log('[AoaTransferClient] complete via AOA bridge');
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
