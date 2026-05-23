import type {
  PairingClaimRequest,
  PairingResponse,
  PairingStateRequest,
} from '@/features/backup/protocols/pairing';
import type {
  TransferAssetExistenceRequest,
  TransferAssetMetadata,
  TransferCompleteRequest,
  TransferResponse,
  TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import { TransportKind } from '@/infrastructure/transport/transport-kind';
import type { TransportStrategy } from '@/infrastructure/transport/transport-strategy';

export class UsbTransportStrategyStub implements TransportStrategy {
  readonly kind = TransportKind.Usb;

  async claim_pairing(_request: PairingClaimRequest): Promise<PairingResponse> {
    throw new Error('USB pairing is not implemented in Phase 2.');
  }

  async get_pairing_state(_request: PairingStateRequest): Promise<PairingResponse> {
    throw new Error('USB pairing state polling is not implemented in Phase 2.');
  }

  async start_transfer(_request: TransferSessionRequest): Promise<TransferResponse> {
    throw new Error('USB transfer start is not implemented in Phase 2.');
  }

  async check_transfer_existence(_request: TransferAssetExistenceRequest): Promise<TransferResponse> {
    throw new Error('USB transfer existence is not implemented in Phase 2.');
  }

  async upload_transfer_asset(
    _metadata: TransferAssetMetadata,
    _content: Uint8Array,
    _stream_state: 'start' | 'chunk' | 'complete'
  ): Promise<TransferResponse> {
    throw new Error('USB transfer asset upload is not implemented in Phase 2.');
  }

  async complete_transfer(_request: TransferCompleteRequest): Promise<TransferResponse> {
    throw new Error('USB transfer completion is not implemented in Phase 2.');
  }
}
