import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import type { PairingResponse } from '@/features/backup/protocols/pairing';
import type { HttpPairingBootstrapClient } from '@/infrastructure/transport/lan/http-pairing-bootstrap-client';
import { DefaultHttpPairingBootstrapClient } from '@/infrastructure/transport/lan/http-pairing-bootstrap-client';
import type { HttpPairingStateClient } from '@/infrastructure/transport/lan/http-pairing-state-client';
import { DefaultHttpPairingStateClient } from '@/infrastructure/transport/lan/http-pairing-state-client';

export interface PairingDeviceIdentity {
  device_uuid: string;
  device_name: string;
  platform: 'android' | 'ios';
}

export interface PairingServiceDeps {
  bootstrap_client: HttpPairingBootstrapClient;
  state_client: HttpPairingStateClient;
}

function default_client_nonce(): string {
  const rand = Math.floor(Math.random() * 1_000_000);
  return `nonce-${Date.now()}-${rand}`;
}

export class PairingService {
  private readonly deps: PairingServiceDeps;

  constructor(endpoint_base_url: string, deps?: Partial<PairingServiceDeps>) {
    this.deps = {
      bootstrap_client: deps?.bootstrap_client ?? new DefaultHttpPairingBootstrapClient(endpoint_base_url),
      state_client: deps?.state_client ?? new DefaultHttpPairingStateClient(endpoint_base_url),
    };
  }

  async claim_pairing(
    payload: PairingQRCodePayload,
    identity: PairingDeviceIdentity,
    capabilities: Record<string, 0 | 1> = {}
  ): Promise<PairingResponse> {
    return this.deps.bootstrap_client.claim({
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
    return this.deps.state_client.state({
      session_id,
      device_uuid,
    });
  }
}
