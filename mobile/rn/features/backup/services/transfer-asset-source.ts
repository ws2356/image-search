import type { TransferAssetMetadata } from '@/features/backup/protocols/transfer';
import type { MediaAssetDescriptor, MediaLibraryGateway } from '@/infrastructure/system/media-library-gateway';
import { StubMediaLibraryGateway } from '@/infrastructure/system/media-library-gateway';

export interface TransferAssetSource {
  enumerate_normalized(batch_size: number): Promise<NormalizedTransferAsset[]>;
  read_asset_chunk(asset_id: string, offset: number, length: number): Promise<Uint8Array>;
}

export interface NormalizedTransferAsset {
  asset_id: string;
  metadata: Omit<TransferAssetMetadata, 'schema' | 'session_id' | 'device_uuid' | 'trust_proof'>;
  dedupe_signature: {
    content_sha1: string | null;
    file_size_bytes: number | null;
    created_at: string | null;
  };
}

function normalize_media_type(value: string | undefined): string {
  if (!value) {
    return 'unknown';
  }
  return value.toLowerCase();
}

function normalize_asset_descriptor(asset: MediaAssetDescriptor): NormalizedTransferAsset {
  const created_at = asset.created_at ?? null;
  const content_sha1 = asset.content_sha1 ?? null;
  const file_size_bytes = asset.file_size_bytes ?? null;
  return {
    asset_id: asset.asset_id,
    metadata: {
      asset_id: asset.asset_id,
      asset_version: asset.asset_version,
      content_sha1: asset.content_sha1,
      file_size_bytes: asset.file_size_bytes,
      filename: asset.filename,
      media_type: normalize_media_type(asset.media_type),
      created_at: asset.created_at,
      updated_at: asset.updated_at,
    },
    dedupe_signature: {
      content_sha1,
      file_size_bytes,
      created_at,
    },
  };
}

export class DefaultTransferAssetSource implements TransferAssetSource {
  private readonly media_library_gateway: MediaLibraryGateway;

  constructor(media_library_gateway: MediaLibraryGateway = new StubMediaLibraryGateway()) {
    this.media_library_gateway = media_library_gateway;
  }

  async enumerate_normalized(batch_size: number): Promise<NormalizedTransferAsset[]> {
    const raw_assets = await this.media_library_gateway.enumerate_transfer_candidates(batch_size);
    return raw_assets.map((asset) => normalize_asset_descriptor(asset));
  }

  async read_asset_chunk(asset_id: string, offset: number, length: number): Promise<Uint8Array> {
    return this.media_library_gateway.read_asset_content_chunk(asset_id, offset, length);
  }
}
