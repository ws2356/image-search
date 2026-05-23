export interface MediaAssetDescriptor {
  asset_id: string;
  asset_version?: string;
  filename: string;
  media_type?: string;
  content_sha1?: string;
  file_size_bytes?: number;
  created_at?: string;
  updated_at?: string;
}

export interface MediaLibraryGateway {
  enumerate_transfer_candidates(batch_size: number): Promise<MediaAssetDescriptor[]>;
  read_asset_content(asset_id: string): Promise<Uint8Array>;
}

export class StubMediaLibraryGateway implements MediaLibraryGateway {
  async enumerate_transfer_candidates(_batch_size: number): Promise<MediaAssetDescriptor[]> {
    return [];
  }

  async read_asset_content(asset_id: string): Promise<Uint8Array> {
    throw new Error(`Media library stub cannot load content for asset_id=${asset_id}.`);
  }
}
