import AsyncStorage from '@react-native-async-storage/async-storage';

export interface TrustedDesktopRecord {
  desktop_id: string;
  desktop_name: string;
  endpoint_base_urls: string[];
  claimed_at: string;
  last_successful_session_id?: string;
}

export interface TrustedDesktopRepository {
  upsert(record: TrustedDesktopRecord): Promise<void>;
  get_by_desktop_id(desktop_id: string): Promise<TrustedDesktopRecord | null>;
  get_latest(): Promise<TrustedDesktopRecord | null>;
}

const TRUSTED_DESKTOP_STORAGE_KEY = 'backup.trustedDesktop';

function is_trusted_desktop_record(value: unknown): value is TrustedDesktopRecord {
  if (typeof value !== 'object' || value == null) {
    return false;
  }
  const candidate = value as Partial<TrustedDesktopRecord>;
  return (
    typeof candidate.desktop_id === 'string' &&
    typeof candidate.desktop_name === 'string' &&
    Array.isArray(candidate.endpoint_base_urls) &&
    candidate.endpoint_base_urls.every((entry) => typeof entry === 'string') &&
    typeof candidate.claimed_at === 'string' &&
    (candidate.last_successful_session_id == null || typeof candidate.last_successful_session_id === 'string')
  );
}

export class AsyncStorageTrustedDesktopRepository implements TrustedDesktopRepository {
  async upsert(record: TrustedDesktopRecord): Promise<void> {
    await AsyncStorage.setItem(TRUSTED_DESKTOP_STORAGE_KEY, JSON.stringify(record));
  }

  async get_by_desktop_id(desktop_id: string): Promise<TrustedDesktopRecord | null> {
    const record = await this.get_latest();
    if (record?.desktop_id !== desktop_id) {
      return null;
    }
    return record;
  }

  async get_latest(): Promise<TrustedDesktopRecord | null> {
    const raw_record = await AsyncStorage.getItem(TRUSTED_DESKTOP_STORAGE_KEY);
    if (raw_record == null) {
      return null;
    }
    const parsed_record: unknown = JSON.parse(raw_record);
    if (!is_trusted_desktop_record(parsed_record)) {
      throw new Error('Persisted trusted desktop data is invalid.');
    }
    return parsed_record;
  }
}

export class InMemoryTrustedDesktopRepository implements TrustedDesktopRepository {
  private readonly records = new Map<string, TrustedDesktopRecord>();

  async upsert(record: TrustedDesktopRecord): Promise<void> {
    this.records.set(record.desktop_id, { ...record });
  }

  async get_by_desktop_id(desktop_id: string): Promise<TrustedDesktopRecord | null> {
    return this.records.get(desktop_id) ?? null;
  }

  async get_latest(): Promise<TrustedDesktopRecord | null> {
    return this.records.values().next().value ?? null;
  }
}
