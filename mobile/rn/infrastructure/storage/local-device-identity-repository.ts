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

export class InMemoryLocalDeviceIdentityRepository implements LocalDeviceIdentityRepository {
  private current: LocalDeviceIdentityRecord | null = null;

  async upsert(record: LocalDeviceIdentityRecord): Promise<void> {
    this.current = { ...record };
  }

  async get_current(): Promise<LocalDeviceIdentityRecord | null> {
    return this.current;
  }
}
