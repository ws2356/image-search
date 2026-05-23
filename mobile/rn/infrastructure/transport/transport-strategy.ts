import type { PairingClaimRequest, PairingResponse, PairingStateRequest } from '@/features/backup/protocols/pairing';
import type {
  TransferAssetExistenceRequest,
  TransferAssetMetadata,
  TransferCompleteRequest,
  TransferResponse,
  TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import type { TransportKind } from '@/infrastructure/transport/transport-kind';

export interface TransportStrategy {
  readonly kind: TransportKind;
  claim_pairing(request: PairingClaimRequest): Promise<PairingResponse>;
  get_pairing_state(request: PairingStateRequest): Promise<PairingResponse>;
  start_transfer(request: TransferSessionRequest): Promise<TransferResponse>;
  check_transfer_existence(request: TransferAssetExistenceRequest): Promise<TransferResponse>;
  upload_transfer_asset(
    metadata: TransferAssetMetadata,
    content: Uint8Array,
    stream_state: 'start' | 'chunk' | 'complete'
  ): Promise<TransferResponse>;
  complete_transfer(request: TransferCompleteRequest): Promise<TransferResponse>;
}
