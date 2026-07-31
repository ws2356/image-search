import type {
  PairingClaimRequest,
  PairingResponse,
  PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import { HttpCapabilityExchangeService } from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import { NoopPayloadCipher, TransferPayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import type { PayloadCipher } from '@/infrastructure/crypto/payload-cipher';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';
import { DefaultHttpPairingBootstrapClient } from '@/infrastructure/transport/lan/http-pairing-bootstrap-client';
import { DefaultHttpPairingStateClient } from '@/infrastructure/transport/lan/http-pairing-state-client';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export class LanTransportStrategy implements TransportStrategy {
  readonly kind = TransportKind.Lan;

  constructor(private readonly endpoint_base_url: string) {}

  async claim_pairing(request: PairingClaimRequest): Promise<PairingResponse> {
    const client = new DefaultHttpPairingBootstrapClient(this.endpoint_base_url);
    return client.claim(request);
  }

  async get_pairing_state(request: PairingStateRequest): Promise<PairingResponse> {
    const client = new DefaultHttpPairingStateClient(this.endpoint_base_url);
    return client.state(request);
  }

  async exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse> {
    const service = new HttpCapabilityExchangeService(fetch);
    return service.exchange(input);
  }

  create_transfer_client(context: TransferServiceContext): TransferClient {
    const payload_cipher: PayloadCipher = context.encryption_enabled
      ? new TransferPayloadCipher(context.trust_key_b64)
      : new NoopPayloadCipher();
    return new DefaultHttpTransferClient(context.endpoint_base_url, fetch, payload_cipher);
  }
}
