export interface MediaAssetDescriptor {
  asset_id: string;
  asset_version?: string;
  filename: string;
  media_type?: string;
  source_uri?: string;
  content_sha1?: string;
  file_size_bytes?: number;
  created_at?: string;
  updated_at?: string;
}

export interface MediaLibraryGateway {
  enumerate_transfer_candidates(batch_size: number): Promise<MediaAssetDescriptor[]>;
  read_asset_content(asset_id: string): Promise<Uint8Array>;
  read_asset_content_chunk(asset_id: string, offset: number, length: number): Promise<Uint8Array>;
}

export class StubMediaLibraryGateway implements MediaLibraryGateway {
  async enumerate_transfer_candidates(_batch_size: number): Promise<MediaAssetDescriptor[]> {
    return [];
  }

  async read_asset_content(asset_id: string): Promise<Uint8Array> {
    throw new Error(`Media library stub cannot load content for asset_id=${asset_id}.`);
  }

  async read_asset_content_chunk(_asset_id: string, _offset: number, _length: number): Promise<Uint8Array> {
    return new Uint8Array();
  }
}
