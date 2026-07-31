import { PAIRING_PROTOCOL_SCHEMA } from '@/features/backup/protocols/pairing';
import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import type { PairingResponse } from '@/features/backup/protocols/pairing';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export interface PairingDeviceIdentity {
  device_uuid: string;
  device_name: string;
  platform: 'android' | 'ios';
}

export interface PairingServiceDeps {
  transport_strategy: TransportStrategy;
}

function default_client_nonce(): string {
  const rand = Math.floor(Math.random() * 1_000_000);
  return `nonce-${Date.now()}-${rand}`;
}

export class PairingService {
  private readonly deps: PairingServiceDeps;

  constructor(deps: PairingServiceDeps) {
    this.deps = deps;
  }

  async claim_pairing(
    payload: PairingQRCodePayload,
    identity: PairingDeviceIdentity,
    capabilities: Record<string, 0 | 1> = {}
  ): Promise<PairingResponse> {
    return this.deps.transport_strategy.claim_pairing({
      schema: PAIRING_PROTOCOL_SCHEMA,
      sid: payload.sessionId,
      opt: payload.oneTimePasscode,
      platform: identity.platform,
      device_uuid: identity.device_uuid,
      device_name: identity.device_name,
      client_nonce: default_client_nonce(),
      capabilities,
    });
  }

  async get_pairing_state(session_id: string, device_uuid: string): Promise<PairingResponse> {
    return this.deps.transport_strategy.get_pairing_state({
      schema: PAIRING_PROTOCOL_SCHEMA,
      session_id,
      device_uuid,
    });
  }
}
