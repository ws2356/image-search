import {
  PAIRING_PROTOCOL_SCHEMA,
  type PairingClaimRequest,
  type PairingResponse,
  type PairingStateRequest,
} from '@/features/backup/protocols/pairing';

export interface LanPairingClient {
  claim(request: PairingClaimRequest): Promise<PairingResponse>;
  state(request: PairingStateRequest): Promise<PairingResponse>;
}

export class FakeLanPairingClient implements LanPairingClient {
  async claim(request: PairingClaimRequest): Promise<PairingResponse> {
    return {
      schema: PAIRING_PROTOCOL_SCHEMA,
      status: 'rejected',
      message: `LAN pairing claim stub is not implemented yet for sid=${request.sid}.`,
      session_id: request.sid,
      device_uuid: request.device_uuid,
    };
  }

  async state(request: PairingStateRequest): Promise<PairingResponse> {
    return {
      schema: PAIRING_PROTOCOL_SCHEMA,
      status: 'waiting',
      message: `LAN pairing state stub is not implemented yet for session_id=${request.session_id}.`,
      session_id: request.session_id,
      device_uuid: request.device_uuid,
    };
  }
}
