import {
  CAPABILITY_EXCHANGE_PATH,
  CAPABILITY_EXCHANGE_SCHEMA,
  type CapabilityExchangeRequest,
  type CapabilityExchangeResponse,
} from '@/features/backup/protocols/capabilities';

type FetchLike = typeof fetch;

function join_base_and_path(base_url: string, path: string): string {
  const trimmed_base = base_url.endsWith('/') ? base_url.slice(0, -1) : base_url;
  return `${trimmed_base}${path}`;
}

export interface CapabilityExchangeServiceInput {
  endpoint_base_url: string;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  capabilities: Record<string, 0 | 1>;
}

export interface CapabilityExchangeService {
  exchange(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse>;
}

export class HttpCapabilityExchangeService implements CapabilityExchangeService {
  private readonly fetch_impl: FetchLike;

  constructor(fetch_impl: FetchLike = fetch) {
    this.fetch_impl = fetch_impl;
  }

  async exchange(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    const request_payload: CapabilityExchangeRequest = {
      schema: CAPABILITY_EXCHANGE_SCHEMA,
      session_id: input.session_id,
      device_uuid: input.device_uuid,
      trust_proof: input.trust_proof,
      capabilities: input.capabilities,
    };
    const response = await this.fetch_impl(join_base_and_path(input.endpoint_base_url, CAPABILITY_EXCHANGE_PATH), {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify(request_payload),
    });
    const payload = (await response.json()) as CapabilityExchangeResponse;
    if (!response.ok) {
      throw new Error(payload.message || `Capability exchange failed with status ${response.status}.`);
    }
    return payload;
  }
}
