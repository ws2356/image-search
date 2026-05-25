import { Platform } from 'react-native';
import * as MediaLibrary from 'expo-media-library';
import { File, FileMode } from 'expo-file-system';

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
  read_asset_content_blob_chunk(asset_id: string, offset: number, length: number): Promise<Blob>;
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
  private readonly uri_cache = new Map<string, string>();

  private async resolve_readable_uri(asset: MediaLibrary.Asset): Promise<string> {
    const direct_uri = await asset.getUri().catch(() => null);
    if (typeof direct_uri === 'string' && direct_uri.length > 0 && !direct_uri.startsWith('content:')) {
      return direct_uri;
    }
    const info = await asset.getInfo();
    if (info.uri && !info.uri.startsWith('content:')) {
      return info.uri;
    }
    if (typeof direct_uri === 'string' && direct_uri.length > 0) {
      return direct_uri;
    }
    if (info.uri) {
      return info.uri;
    }
    throw new Error(`Media library asset ${asset.id} has no readable URI.`);
  }

  private async resolve_asset_uri(asset_id: string): Promise<string> {
    const cached = this.uri_cache.get(asset_id);
    if (cached) {
      return cached;
    }
    const asset = new MediaLibrary.Asset(asset_id);
    const uri = await this.resolve_readable_uri(asset);
    this.uri_cache.set(asset_id, uri);
    return uri;
  }

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
        const uri = await this.resolve_readable_uri(asset);
        this.uri_cache.set(asset.id, uri);
        let file_size_bytes: number | undefined;
        try {
          const resolved_size = new File(uri).size;
          file_size_bytes = resolved_size > 0 ? resolved_size : undefined;
        } catch {
          file_size_bytes = undefined;
        }
        return {
          asset_id: asset.id,
          asset_version: info.modificationTime != null ? String(info.modificationTime) : undefined,
          filename: info.filename || `${asset.id}.bin`,
          media_type: media_type_to_string(info.mediaType),
          source_uri: uri,
          file_size_bytes,
          created_at: to_iso_from_millis(info.creationTime ?? undefined),
          updated_at: to_iso_from_millis(info.modificationTime ?? undefined),
        } satisfies MediaAssetDescriptor;
      })
    );
    return descriptors;
  }

  async read_asset_content(asset_id: string): Promise<Uint8Array> {
    const uri = await this.resolve_asset_uri(asset_id);
    return fetch_asset_bytes(uri);
  }

  async read_asset_content_chunk(asset_id: string, offset: number, length: number): Promise<Uint8Array> {
    const uri = await this.resolve_asset_uri(asset_id);
    const file = new File(uri);
    const safe_offset = Math.max(0, offset);
    const safe_end = Math.max(safe_offset, safe_offset + Math.max(0, length));
    const read_length = Math.max(0, safe_end - safe_offset);
    try {
      const handle = file.open(FileMode.ReadOnly);
      try {
        handle.offset = safe_offset;
        const chunk = handle.readBytes(read_length);
        console.log('[Transfer][MediaChunk]', {
          asset_id,
          uri_scheme: uri.split(':', 1)[0] ?? 'unknown',
          offset: safe_offset,
          end: safe_end,
          chunk_size: chunk.length,
          chunk_ctor: (chunk as unknown as { constructor?: { name?: string } }).constructor?.name ?? 'unknown',
        });
        return chunk;
      } finally {
        handle.close();
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(
        `Failed creating media chunk for asset ${asset_id} (uri=${uri}, offset=${safe_offset}, end=${safe_end}): ${message}`
      );
    }
  }

  async read_asset_content_blob_chunk(asset_id: string, offset: number, length: number): Promise<Blob> {
    const chunk = await this.read_asset_content_chunk(asset_id, offset, length);
    try {
      return new Blob([chunk]);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.log('[Transfer][MediaChunk]', {
        asset_id,
        offset,
        end: offset + length,
        chunk_size: chunk.length,
        chunk_ctor: (chunk as unknown as { constructor?: { name?: string } }).constructor?.name ?? 'unknown',
        blob_wrap_error: message,
      });
      throw new Error(`Failed wrapping media chunk into Blob for asset ${asset_id}: ${message}`);
    }
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

  async read_asset_content_blob_chunk(_asset_id: string, _offset: number, _length: number): Promise<Blob> {
    return new Blob();
  }
}

export function create_default_media_library_gateway(): MediaLibraryGateway {
  if (Platform.OS === 'android') {
    return new ExpoMediaLibraryGateway();
  }
  return new StubMediaLibraryGateway();
}
