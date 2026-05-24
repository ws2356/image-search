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

type FetchLike = typeof fetch;

function join_base_and_path(base_url: string, path: string): string {
  const trimmed_base = base_url.endsWith('/') ? base_url.slice(0, -1) : base_url;
  return `${trimmed_base}${path}`;
}

export interface HttpTransferClient {
  start(request: Omit<TransferSessionRequest, 'schema'>): Promise<TransferResponse>;
  existence(request: Omit<TransferAssetExistenceRequest, 'schema'>): Promise<TransferResponse>;
  asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Uint8Array
  ): Promise<TransferResponse>;
  complete(request: Omit<TransferCompleteRequest, 'schema'>): Promise<TransferResponse>;
}

export class DefaultHttpTransferClient implements HttpTransferClient {
  private readonly base_url: string;
  private readonly fetch_impl: FetchLike;

  constructor(base_url: string, fetch_impl: FetchLike = fetch) {
    this.base_url = base_url;
    this.fetch_impl = fetch_impl;
  }

  async start(request: Omit<TransferSessionRequest, 'schema'>): Promise<TransferResponse> {
    const response = await this.fetch_impl(join_base_and_path(this.base_url, MOBILE_TRANSFER_START_PATH), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        schema: MOBILE_TRANSFER_SCHEMA,
        ...request,
      } satisfies TransferSessionRequest),
    });
    return this.parse_response(response, 'Transfer start request failed.');
  }

  async existence(request: Omit<TransferAssetExistenceRequest, 'schema'>): Promise<TransferResponse> {
    const response = await this.fetch_impl(join_base_and_path(this.base_url, MOBILE_TRANSFER_EXISTENCE_PATH), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        schema: MOBILE_TRANSFER_SCHEMA,
        ...request,
      } satisfies TransferAssetExistenceRequest),
    });
    return this.parse_response(response, 'Transfer existence request failed.');
  }

  async asset(
    metadata: TransferAssetMetadata,
    request_id: string,
    stream_state: 'start' | 'chunk' | 'complete',
    content?: Uint8Array
  ): Promise<TransferResponse> {
    const url = new URL(join_base_and_path(this.base_url, MOBILE_TRANSFER_ASSET_PATH));
    url.searchParams.set('request_id', request_id);
    url.searchParams.set('stream_state', stream_state);
    const chunk_body = stream_state === 'chunk' ? new Uint8Array(content ?? new Uint8Array()).buffer : null;
    const response = await this.fetch_impl(
      url.toString(),
      {
        method: 'POST',
        headers:
          stream_state === 'chunk'
            ? { 'content-type': 'application/octet-stream' }
            : { 'content-type': 'application/json' },
        body:
          chunk_body ??
          JSON.stringify({
            ...metadata,
            stream_state,
            request_id,
          }),
      }
    );
    return this.parse_response(response, 'Transfer asset request failed.');
  }

  async complete(request: Omit<TransferCompleteRequest, 'schema'>): Promise<TransferResponse> {
    const response = await this.fetch_impl(join_base_and_path(this.base_url, MOBILE_TRANSFER_COMPLETE_PATH), {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        schema: MOBILE_TRANSFER_SCHEMA,
        ...request,
      } satisfies TransferCompleteRequest),
    });
    return this.parse_response(response, 'Transfer complete request failed.');
  }

  private async parse_response(response: Response, fallback_message: string): Promise<TransferResponse> {
    const payload = (await response.json()) as TransferResponse;
    if (!response.ok) {
      throw new Error(payload.message || `${fallback_message} Status=${response.status}.`);
    }
    return payload;
  }
}
