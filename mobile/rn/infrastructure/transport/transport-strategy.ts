import type {
  PairingClaimRequest,
  PairingResponse,
  PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  CapabilityExchangeResponse,
  CapabilityExchangeServiceInput,
} from '@/features/backup/services/capability-exchange-service';
import type { TransferClient } from '@/features/backup/services/transfer-client';
import type { TransferServiceContext } from '@/features/backup/services/transfer-service';
import type { TransportKind } from '@/infrastructure/transport/transport-kind';

export interface TransportStrategy {
  readonly kind: TransportKind;
  claim_pairing(request: PairingClaimRequest): Promise<PairingResponse>;
  get_pairing_state(request: PairingStateRequest): Promise<PairingResponse>;
  exchange_capabilities(input: CapabilityExchangeServiceInput): Promise<CapabilityExchangeResponse>;
  create_transfer_client(context: TransferServiceContext): TransferClient;
}
