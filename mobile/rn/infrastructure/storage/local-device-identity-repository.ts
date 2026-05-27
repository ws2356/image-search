import AsyncStorage from '@react-native-async-storage/async-storage';

export interface LocalDeviceIdentityRecord {
  device_uuid: string;
  device_name: string;
  platform: 'android' | 'ios';
  updated_at: string;
}

export interface LocalDeviceIdentityRepository {
  upsert(record: LocalDeviceIdentityRecord): Promise<void>;
  get_current(): Promise<LocalDeviceIdentityRecord | null>;
}

const LOCAL_DEVICE_IDENTITY_STORAGE_KEY = 'backup.localDeviceIdentity';

function is_local_device_identity_record(value: unknown): value is LocalDeviceIdentityRecord {
  if (typeof value !== 'object' || value == null) {
    return false;
  }
  const candidate = value as Partial<LocalDeviceIdentityRecord>;
  return (
    typeof candidate.device_uuid === 'string' &&
    typeof candidate.device_name === 'string' &&
    (candidate.platform === 'android' || candidate.platform === 'ios') &&
    typeof candidate.updated_at === 'string'
  );
}

export class AsyncStorageLocalDeviceIdentityRepository implements LocalDeviceIdentityRepository {
  async upsert(record: LocalDeviceIdentityRecord): Promise<void> {
    await AsyncStorage.setItem(LOCAL_DEVICE_IDENTITY_STORAGE_KEY, JSON.stringify(record));
  }

  async get_current(): Promise<LocalDeviceIdentityRecord | null> {
    const raw_record = await AsyncStorage.getItem(LOCAL_DEVICE_IDENTITY_STORAGE_KEY);
    if (raw_record == null) {
      return null;
    }
    const parsed_record: unknown = JSON.parse(raw_record);
    if (!is_local_device_identity_record(parsed_record)) {
      throw new Error('Persisted local device identity is invalid.');
    }
    return parsed_record;
  }
}

export class InMemoryLocalDeviceIdentityRepository implements LocalDeviceIdentityRepository {
  private current: LocalDeviceIdentityRecord | null = null;

  async upsert(record: LocalDeviceIdentityRecord): Promise<void> {
    this.current = { ...record };
  }

  async get_current(): Promise<LocalDeviceIdentityRecord | null> {
    return this.current;
  }
}
