export const PAIRING_PROTOCOL_SCHEMA = 'dtis.mobile-pairing.v1' as const;
export const PAIRING_CLAIM_PATH = '/api/mobile/pairing/claim' as const;
export const PAIRING_STATE_PATH = '/api/mobile/pairing/state' as const;

export type PairingPlatform = 'android' | 'ios';
export type PairingTransport = 'lan' | 'usb';

export interface PairingQrPayloadFields {
  v: string;
  ept: string;
  sid: string;
  opt: string;
  usp: string;
  sec?: string;
}

export interface PairingClaimRequest {
  schema: typeof PAIRING_PROTOCOL_SCHEMA;
  sid: string;
  opt: string;
  platform: PairingPlatform;
  device_uuid: string;
  device_name: string;
  client_nonce: string;
  capabilities?: Record<string, 0 | 1>;
}

export interface PairingStateRequest {
  schema: typeof PAIRING_PROTOCOL_SCHEMA;
  session_id: string;
  device_uuid: string;
}

export interface PairingResponse {
  schema: typeof PAIRING_PROTOCOL_SCHEMA;
  status:
    | 'accepted'
    | 'waiting'
    | 'pairing_mismatched'
    | 'pairing_stopped'
    | 'rejected'
    | 'expired';
  message: string;
  session_id?: string;
  device_uuid?: string;
  device_name?: string;
  folder_path?: string;
  transport?: PairingTransport;
  capabilities?: Record<string, 0 | 1>;
}
