import {
  MOBILE_TRANSFER_ASSET_PATH,
  MOBILE_TRANSFER_COMPLETE_PATH,
  MOBILE_TRANSFER_EXISTENCE_PATH,
  MOBILE_TRANSFER_SCHEMA,
  MOBILE_TRANSFER_START_PATH,
  type TransferAssetExistenceRequest,
  type TransferAssetMetadata,
  type TransferCompleteRequest,
  type TransferResponse,
  type TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { PayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import { NoopPayloadCipher } from '@/infrastructure/crypto/payload-cipher';

type FetchLike = typeof fetch;

function join_base_and_path(base_url: string, path: string): string {
  const trimmed_base = base_url.endsWith('/') ? base_url.slice(0, -1) : base_url;
  return `${trimmed_base}${path}`;
}

function describe_network_error(error: unknown): string {
  if (error instanceof Error) {
    const cause = error.cause instanceof Error ? ` (cause: ${error.cause.message})` : '';
    return `[TransferHttp] ${error.message}${cause}`;
  }
  return `[TransferHttp] ${String(error)}`;
}

export interface HttpTransferClient {
  start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
  existence(request: Omit<TransferAssetExistenceRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
  asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse>;
  complete(request: Omit<TransferCompleteRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse>;
}

export class DefaultHttpTransferClient implements HttpTransferClient, TransferClient {
  private readonly base_url: string;
  private readonly fetch_impl: FetchLike;
  private readonly payload_cipher: PayloadCipher;

  constructor(base_url: string, fetch_impl: FetchLike = fetch, payload_cipher: PayloadCipher = new NoopPayloadCipher()) {
    this.base_url = base_url;
    this.fetch_impl = fetch_impl;
    this.payload_cipher = payload_cipher;
  }

  private is_blob_like(value: unknown): value is Blob {
    return (
      typeof value === 'object' &&
      value !== null &&
      typeof (value as { size?: unknown }).size === 'number' &&
      typeof (value as { arrayBuffer?: unknown }).arrayBuffer === 'function'
    );
  }

  async start(request: Omit<TransferSessionRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    const payload = await this.payload_cipher.encrypt_json_payload({
      schema: MOBILE_TRANSFER_SCHEMA,
      ...request,
    } satisfies TransferSessionRequest);
    const url = join_base_and_path(this.base_url, MOBILE_TRANSFER_START_PATH);
    console.log(`[TransferHttp] POST ${url}`);
    let response: Response;
    try {
      response = await this.fetch_impl(url, {
        method: 'POST',
        signal: abort_signal,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
    } catch (error) {
      console.warn(describe_network_error(error), url);
      throw error;
    }
    console.log(`[TransferHttp] POST ${url} -> status=${response.status}`);
    return this.parse_response(response, 'Transfer start request failed.');
  }

  async existence(
    request: Omit<TransferAssetExistenceRequest, 'schema'>,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    const payload = await this.payload_cipher.encrypt_json_payload({
      schema: MOBILE_TRANSFER_SCHEMA,
      ...request,
    } satisfies TransferAssetExistenceRequest);
    const url = join_base_and_path(this.base_url, MOBILE_TRANSFER_EXISTENCE_PATH);
    console.log(`[TransferHttp] POST ${url}`);
    let response: Response;
    try {
      response = await this.fetch_impl(url, {
        method: 'POST',
        signal: abort_signal,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
    } catch (error) {
      console.warn(describe_network_error(error), url);
      throw error;
    }
    console.log(`[TransferHttp] POST ${url} -> status=${response.status}`);
    return this.parse_response(response, 'Transfer existence request failed.');
  }

  async asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    const url = new URL(join_base_and_path(this.base_url, MOBILE_TRANSFER_ASSET_PATH));
    url.searchParams.set('request_id', request_id);
    url.searchParams.set('stream_state', stream_state);
    if (stream_state === 'chunk') {
      if (content == null) {
        throw new Error('Transfer asset request failed: missing chunk content.');
      }
      if (!(content instanceof Uint8Array) && !this.is_blob_like(content)) {
        throw new Error('Transfer asset request failed: unsupported chunk content type.');
      }
      const encrypted_chunk = await this.payload_cipher.encrypt_binary_chunk(content);
      return this.post_chunk_with_xhr(url.toString(), encrypted_chunk, abort_signal);
    }
    const payload = await this.payload_cipher.encrypt_json_payload({
      ...metadata,
      stream_state,
      request_id,
    });
    console.log(`[TransferHttp] POST ${url.toString()}`);
    let response: Response;
    try {
      response = await this.fetch_impl(
        url.toString(),
        {
          method: 'POST',
          signal: abort_signal,
          headers: { 'content-type': 'application/json' },
          body:
            JSON.stringify(payload),
        }
      );
    } catch (error) {
      console.warn(describe_network_error(error), url.toString());
      throw error;
    }
    console.log(`[TransferHttp] POST ${url.toString()} -> status=${response.status}`);
    return this.parse_response(response, 'Transfer asset request failed.');
  }

  private async post_chunk_with_xhr(
    url: string,
    content: Blob | Uint8Array,
    abort_signal?: AbortSignal
  ): Promise<TransferResponse> {
    return new Promise<TransferResponse>((resolve, reject) => {
      const request = new XMLHttpRequest();
      if (abort_signal?.aborted) {
        reject(new Error('Transfer stopped by user.'));
        return;
      }
      request.open('POST', url);
      request.setRequestHeader('content-type', 'application/octet-stream');
      const on_abort = () => {
        request.abort();
        reject(new Error('Transfer stopped by user.'));
      };
      abort_signal?.addEventListener('abort', on_abort, { once: true });
      request.onreadystatechange = () => {
        if (request.readyState !== XMLHttpRequest.DONE) {
          return;
        }
        abort_signal?.removeEventListener('abort', on_abort);
        const raw_response = request.responseText || '';
        let parsed_payload: object;
        try {
          parsed_payload = JSON.parse(raw_response) as object;
        } catch {
          console.warn(`[TransferHttp] chunk POST ${url} failed: status=${request.status} raw=${raw_response.slice(0, 200)}`);
          reject(new Error(`Transfer asset request failed. Status=${request.status}. Raw=${raw_response}`));
          return;
        }
        this.payload_cipher.decrypt_json_payload(parsed_payload).then((decoded_payload) => {
          const payload = decoded_payload as TransferResponse;
          if (request.status >= 200 && request.status < 300) {
            resolve(payload);
            return;
          }
          console.warn(`[TransferHttp] chunk POST ${url} failed: status=${request.status} message=${payload.message}`);
          reject(new Error(payload.message || `Transfer asset request failed. Status=${request.status}.`));
        }).catch((error) => {
          const message = error instanceof Error ? error.message : 'Transfer asset request failed: response decode error.';
          console.warn(`[TransferHttp] chunk POST ${url} decode failed: ${message}`);
          reject(new Error(message));
        });
      };
      request.onerror = () => {
        abort_signal?.removeEventListener('abort', on_abort);
        console.warn(`[TransferHttp] chunk POST ${url} failed: network transport error`);
        reject(new Error('Transfer asset request failed due to a network transport error.'));
      };
      request.send(content as unknown as BodyInit);
    });
  }

  async complete(request: Omit<TransferCompleteRequest, 'schema'>, abort_signal?: AbortSignal): Promise<TransferResponse> {
    const payload = await this.payload_cipher.encrypt_json_payload({
      schema: MOBILE_TRANSFER_SCHEMA,
      ...request,
    } satisfies TransferCompleteRequest);
    const url = join_base_and_path(this.base_url, MOBILE_TRANSFER_COMPLETE_PATH);
    console.log(`[TransferHttp] POST ${url}`);
    let response: Response;
    try {
      response = await this.fetch_impl(url, {
        method: 'POST',
        signal: abort_signal,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
    } catch (error) {
      console.warn(describe_network_error(error), url);
      throw error;
    }
    console.log(`[TransferHttp] POST ${url} -> status=${response.status}`);
    return this.parse_response(response, 'Transfer complete request failed.');
  }

  private async parse_response(response: Response, fallback_message: string): Promise<TransferResponse> {
    const decoded_payload = await this.payload_cipher.decrypt_json_payload((await response.json()) as object);
    const payload = decoded_payload as TransferResponse;
    if (!response.ok) {
      throw new Error(payload.message || `${fallback_message} Status=${response.status}.`);
    }
    return payload;
  }
}
