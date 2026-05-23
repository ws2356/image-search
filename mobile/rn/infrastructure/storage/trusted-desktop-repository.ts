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
}

export class InMemoryTrustedDesktopRepository implements TrustedDesktopRepository {
  private readonly records = new Map<string, TrustedDesktopRecord>();

  async upsert(record: TrustedDesktopRecord): Promise<void> {
    this.records.set(record.desktop_id, { ...record });
  }

  async get_by_desktop_id(desktop_id: string): Promise<TrustedDesktopRecord | null> {
    return this.records.get(desktop_id) ?? null;
  }
}
