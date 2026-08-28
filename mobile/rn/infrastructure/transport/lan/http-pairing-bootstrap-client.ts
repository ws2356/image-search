import {
  PAIRING_CLAIM_PATH,
  PAIRING_PROTOCOL_SCHEMA,
  type PairingClaimRequest,
  type PairingResponse,
} from '@/features/backup/protocols/pairing';

type FetchLike = typeof fetch;

function join_base_and_path(base_url: string, path: string): string {
  const trimmed_base = base_url.endsWith('/') ? base_url.slice(0, -1) : base_url;
  return `${trimmed_base}${path}`;
}

export interface HttpPairingBootstrapClient {
  claim(request: Omit<PairingClaimRequest, 'schema'>): Promise<PairingResponse>;
}

export class DefaultHttpPairingBootstrapClient implements HttpPairingBootstrapClient {
  private readonly base_url: string;
  private readonly fetch_impl: FetchLike;

  constructor(base_url: string, fetch_impl: FetchLike = fetch) {
    this.base_url = base_url;
    this.fetch_impl = fetch_impl;
  }

  async claim(request: Omit<PairingClaimRequest, 'schema'>): Promise<PairingResponse> {
    const response = await this.fetch_impl(join_base_and_path(this.base_url, PAIRING_CLAIM_PATH), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        schema: PAIRING_PROTOCOL_SCHEMA,
        ...request,
      } satisfies PairingClaimRequest),
    });

    const payload = (await response.json()) as PairingResponse;
    if (!response.ok) {
      throw new Error(payload.message || `Pairing claim failed with status ${response.status}.`);
    }
    return payload;
  }
}
