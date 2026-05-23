export interface BackupHistoryRecord {
  session_id: string;
  completed_at: string;
  transferred_count: number;
  failed_count: number;
}

export interface BackupHistoryRepository {
  append(record: BackupHistoryRecord): Promise<void>;
  list_recent(limit: number): Promise<BackupHistoryRecord[]>;
}

export class InMemoryBackupHistoryRepository implements BackupHistoryRepository {
  private readonly records: BackupHistoryRecord[] = [];

  async append(record: BackupHistoryRecord): Promise<void> {
    this.records.unshift({ ...record });
  }

  async list_recent(limit: number): Promise<BackupHistoryRecord[]> {
    return this.records.slice(0, Math.max(0, limit));
  }
}
