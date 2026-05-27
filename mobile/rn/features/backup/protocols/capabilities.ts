export const CAPABILITY_EXCHANGE_SCHEMA = 'dtis.mobile-capabilities.v1' as const;
export const CAPABILITY_EXCHANGE_PATH = '/api/mobile/capabilities/exchange' as const;
export const CAPABILITY_EXCHANGE_PROOF_PURPOSE = 'capabilities.exchange' as const;
export const TRANSFER_EXISTENCE_ASSET_VERSION_CAPABILITY = 'transfer_existence_asset_version_v1' as const;

export interface CapabilityExchangeRequest {
  schema: typeof CAPABILITY_EXCHANGE_SCHEMA;
  session_id: string;
  device_uuid: string;
  trust_proof: string;
  capabilities: Record<string, 0 | 1>;
}

export interface CapabilityExchangeResponse {
  schema: typeof CAPABILITY_EXCHANGE_SCHEMA;
  status: 'accepted' | 'rejected';
  message: string;
  session_id?: string;
  device_uuid?: string;
  capabilities: Record<string, 0 | 1>;
}
