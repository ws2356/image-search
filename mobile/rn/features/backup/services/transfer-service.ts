import { MOBILE_TRANSFER_SCHEMA } from '@/features/backup/protocols/transfer';
import type {
  TransferAssetExistenceRequest,
  TransferAssetMetadata,
  TransferAssetSignature,
  TransferCompleteRequest,
  TransferResponse,
  TransferSessionRequest,
} from '@/features/backup/protocols/transfer';
import type { TrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import { DefaultTrustProofSigner } from '@/infrastructure/crypto/trust-proof-signer';
import type { HttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';
import { DefaultHttpTransferClient } from '@/infrastructure/transport/lan/http-transfer-client';

export interface TransferServiceContext {
  endpoint_base_url: string;
  session_id: string;
  device_uuid: string;
  trust_key_b64: string;
}

export interface TransferServiceDeps {
  transfer_client: HttpTransferClient;
  trust_proof_signer: TrustProofSigner;
}

export class TransferService {
  private readonly context: TransferServiceContext;
  private readonly deps: TransferServiceDeps;

  constructor(context: TransferServiceContext, deps?: Partial<TransferServiceDeps>) {
    this.context = context;
    this.deps = {
      transfer_client: deps?.transfer_client ?? new DefaultHttpTransferClient(context.endpoint_base_url),
      trust_proof_signer: deps?.trust_proof_signer ?? new DefaultTrustProofSigner(),
    };
  }

  async start(total_assets: number): Promise<TransferResponse> {
    const trust_proof = await this.build_transfer_trust_proof('transfer.start');
    const request: Omit<TransferSessionRequest, 'schema'> = {
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      total_assets,
      transferred_count: 0,
      failed_count: 0,
    };
    return this.deps.transfer_client.start(request);
  }

  async check_existence(assets: TransferAssetSignature[]): Promise<TransferResponse> {
    const trust_proof = await this.build_transfer_trust_proof('transfer.existence');
    const request: Omit<TransferAssetExistenceRequest, 'schema'> = {
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      assets,
    };
    return this.deps.transfer_client.existence(request);
  }

  async upload_asset(
    metadata: Omit<TransferAssetMetadata, 'schema' | 'session_id' | 'device_uuid' | 'trust_proof'>,
    content: Uint8Array
  ): Promise<TransferResponse> {
    const request_id = metadata.asset_id;
    const trust_proof = await this.build_transfer_trust_proof('transfer.asset');
    const full_metadata: TransferAssetMetadata = {
      schema: MOBILE_TRANSFER_SCHEMA,
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      ...metadata,
    };
    await this.deps.transfer_client.asset(full_metadata, request_id, 'start');
    if (content.length > 0) {
      await this.deps.transfer_client.asset(full_metadata, request_id, 'chunk', content);
    }
    return this.deps.transfer_client.asset(full_metadata, request_id, 'complete');
  }

  async complete(transferred_count: number, failed_count: number): Promise<TransferResponse> {
    const trust_proof = await this.build_transfer_trust_proof('transfer.complete');
    const request: Omit<TransferCompleteRequest, 'schema'> = {
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_proof,
      transferred_count,
      failed_count,
    };
    return this.deps.transfer_client.complete(request);
  }

  private async build_transfer_trust_proof(
    purpose: 'transfer.start' | 'transfer.existence' | 'transfer.asset' | 'transfer.complete'
  ): Promise<string> {
    return this.deps.trust_proof_signer.derive_trust_proof({
      purpose,
      schema: MOBILE_TRANSFER_SCHEMA,
      session_id: this.context.session_id,
      device_uuid: this.context.device_uuid,
      trust_key_b64: this.context.trust_key_b64,
    });
  }
}
