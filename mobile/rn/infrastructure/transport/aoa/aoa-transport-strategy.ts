import {
  PAIRING_PROTOCOL_SCHEMA,
  type PairingClaimRequest,
  type PairingResponse,
  type PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { AoaTransferClient } from '@/infrastructure/transport/aoa/aoa-transfer-client';
import type { AoaBridge } from '@/infrastructure/transport/aoa/aoa-bridge';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

const MOBILE_TRANSPORT_SCHEMA = 'dtis.mobile-transport.v1';

export class AoaTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  constructor(
    private readonly bridge: AoaBridge,
    private readonly qr_payload: { sessionId: string; oneTimePasscode: string; suggestedUsbPort?: number }
  ) {}

  async prepare_bootstrap(): Promise<void> {
    const port = this.qr_payload.suggestedUsbPort ?? 45000;
    return this.bridge.prepareBootstrap(this.qr_payload.sessionId, this.qr_payload.oneTimePasscode, port);
  }

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    await this.prepare_bootstrap();
    const response = await this.bridge.sendRequest(JSON.stringify(this.envelope('pairing.claim', request)));
    return this.parse_pairing_response(response);
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    const response = await this.bridge.sendRequest(JSON.stringify(this.envelope('pairing.state', request)));
    return this.parse_pairing_response(response);
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    const body = {
      schema: 'dtis.mobile-capabilities.v1',
      session_id: input.session_id,
      device_uuid: input.device_uuid,
      trust_proof: input.trust_proof,
      capabilities: { ...input.capabilities, aoa_transfer: 1 },
    };
    const response = await this.bridge.sendRequest(JSON.stringify(this.envelope('capabilities.exchange', body)));
    return JSON.parse(response).body as CapabilityExchangeResponse;
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    return new AoaTransferClient(this.bridge, context);
  }

  private envelope(operation: string, body: object, request_id?: string) {
    return {
      schema: MOBILE_TRANSPORT_SCHEMA,
      operation,
      request_id: request_id ?? this.generate_request_id(),
      body_schema: PAIRING_PROTOCOL_SCHEMA,
      body,
    };
  }

  private parse_pairing_response(raw: string): PairingResponse {
    const parsed = JSON.parse(raw);
    return parsed.body as PairingResponse;
  }

  private generate_request_id(): string {
    return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}
