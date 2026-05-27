import {
  CAPABILITY_EXCHANGE_SCHEMA,
  type CapabilityExchangeRequest,
} from '@/features/backup/protocols/capabilities';
import {
  PAIRING_PROTOCOL_SCHEMA,
  type PairingClaimRequest,
  type PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import {
  MOBILE_TRANSFER_SCHEMA,
  type TransferAssetExistenceRequest,
  type TransferCompleteRequest,
  type TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import {
  MOBILE_UPDATE_PROMPT_SCHEMA,
  type UpdatePromptRequest,
} from '@/features/backup/protocols/update-prompt';

export const FIXTURE_PAIRING_CLAIM_REQUEST: PairingClaimRequest = {
  schema: PAIRING_PROTOCOL_SCHEMA,
  sid: 'session-123',
  opt: '123456',
  platform: 'android',
  device_uuid: 'device-123',
  device_name: 'Pixel 9',
  client_nonce: 'nonce-123',
  capabilities: {
    encrypted_payload_v1: 1,
  },
};

export const FIXTURE_PAIRING_STATE_REQUEST: PairingStateRequest = {
  schema: PAIRING_PROTOCOL_SCHEMA,
  session_id: 'session-123',
  device_uuid: 'device-123',
};

export const FIXTURE_CAPABILITY_EXCHANGE_REQUEST: CapabilityExchangeRequest = {
  schema: CAPABILITY_EXCHANGE_SCHEMA,
  session_id: 'session-123',
  device_uuid: 'device-123',
  trust_proof: 'proof-123',
  capabilities: {
    encrypted_payload_v1: 1,
  },
};

export const FIXTURE_TRANSFER_START_REQUEST: TransferSessionRequest = {
  schema: MOBILE_TRANSFER_SCHEMA,
  session_id: 'session-123',
  device_uuid: 'device-123',
  trust_proof: 'proof-123',
  total_assets: 42,
  transferred_count: 0,
  failed_count: 0,
};

export const FIXTURE_TRANSFER_EXISTENCE_REQUEST: TransferAssetExistenceRequest = {
  schema: MOBILE_TRANSFER_SCHEMA,
  session_id: 'session-123',
  device_uuid: 'device-123',
  trust_proof: 'proof-123',
  assets: [
    {
      asset_id: 'asset-1',
      sha1: 'deadbeef',
      file_size: 1024,
      created_at: '2026-01-01T00:00:00Z',
    },
  ],
};

export const FIXTURE_TRANSFER_COMPLETE_REQUEST: TransferCompleteRequest = {
  schema: MOBILE_TRANSFER_SCHEMA,
  session_id: 'session-123',
  device_uuid: 'device-123',
  trust_proof: 'proof-123',
  transferred_count: 40,
  failed_count: 2,
};

export const FIXTURE_UPDATE_PROMPT_REQUEST: UpdatePromptRequest = {
  schema: MOBILE_UPDATE_PROMPT_SCHEMA,
  session_id: 'session-123',
  device_uuid: 'device-123',
  trust_proof: 'proof-123',
  required: true,
  body_text: 'Please update the mobile app.',
  update_destination: 'https://example.com/update',
};
