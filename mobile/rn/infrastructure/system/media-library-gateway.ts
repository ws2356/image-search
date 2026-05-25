import { Platform } from 'react-native';
import * as MediaLibrary from 'expo-media-library';

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

function media_type_to_string(media_type: MediaLibrary.MediaType | string | undefined): string | undefined {
  if (media_type === MediaLibrary.MediaType.IMAGE || media_type === 'photo' || media_type === 'image') {
    return 'photo';
  }
  if (media_type === MediaLibrary.MediaType.VIDEO || media_type === 'video') {
    return 'video';
  }
  return undefined;
}

function to_iso_from_millis(millis: number | undefined): string | undefined {
  if (typeof millis !== 'number' || !Number.isFinite(millis) || millis <= 0) {
    return undefined;
  }
  const epoch_millis = millis < 10_000_000_000 ? millis * 1000 : millis;
  return new Date(epoch_millis).toISOString();
}

async function fetch_asset_bytes(asset_uri: string): Promise<Uint8Array> {
  const response = await fetch(asset_uri);
  if (!response.ok) {
    throw new Error(`Failed to read media content from ${asset_uri}.`);
  }
  const buffer = await response.arrayBuffer();
  return new Uint8Array(buffer);
}

export class ExpoMediaLibraryGateway implements MediaLibraryGateway {
  async enumerate_transfer_candidates(batch_size: number): Promise<MediaAssetDescriptor[]> {
    const page_size = Math.max(1, Math.min(batch_size, 5000));
    const assets = await new MediaLibrary.Query()
      .within(MediaLibrary.AssetField.MEDIA_TYPE, [MediaLibrary.MediaType.IMAGE, MediaLibrary.MediaType.VIDEO])
      .orderBy({ key: MediaLibrary.AssetField.CREATION_TIME, ascending: true })
      .limit(page_size)
      .exe();

    const descriptors = await Promise.all(
      assets.map(async (asset) => {
        const info = await asset.getInfo();
        return {
          asset_id: asset.id,
          asset_version: info.modificationTime != null ? String(info.modificationTime) : undefined,
          filename: info.filename || `${asset.id}.bin`,
          media_type: media_type_to_string(info.mediaType),
          source_uri: info.uri,
          created_at: to_iso_from_millis(info.creationTime ?? undefined),
          updated_at: to_iso_from_millis(info.modificationTime ?? undefined),
        } satisfies MediaAssetDescriptor;
      })
    );
    return descriptors;
  }

  async read_asset_content(asset_id: string): Promise<Uint8Array> {
    const asset = new MediaLibrary.Asset(asset_id);
    const info = await asset.getInfo();
    const uri = info.uri;
    if (!uri) {
      throw new Error(`Media library asset ${asset_id} has no readable URI.`);
    }
    return fetch_asset_bytes(uri);
  }

  async read_asset_content_chunk(asset_id: string, offset: number, length: number): Promise<Uint8Array> {
    const content = await this.read_asset_content(asset_id);
    const safe_offset = Math.max(0, offset);
    const safe_end = Math.max(safe_offset, safe_offset + Math.max(0, length));
    return content.slice(safe_offset, safe_end);
  }
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

export function create_default_media_library_gateway(): MediaLibraryGateway {
  if (Platform.OS === 'android') {
    return new ExpoMediaLibraryGateway();
  }
  return new StubMediaLibraryGateway();
}
