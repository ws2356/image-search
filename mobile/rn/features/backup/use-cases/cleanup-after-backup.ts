import type { MediaLibraryGateway } from '@/infrastructure/system/media-library-gateway';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';

export interface CleanupAfterBackupDeps {
  media_library_gateway: MediaLibraryGateway;
}

export type CleanupAfterBackupResult =
  | { kind: 'skipped' }
  | { kind: 'removed'; removedCount: number }
  | { kind: 'failed'; message: string };

/**
 * Deletes the assets that were successfully transferred (or passed the desktop
 * existence check) during the just-completed backup session. Deletion is gated
 * on the user's remove-after-backup preference and is strictly limited to the
 * asset ids recorded for this session, so failed or never-processed items are
 * never removed.
 */
export async function cleanupAfterBackup(
  successfullyTransferredAssetIds: string[],
  deps: CleanupAfterBackupDeps
): Promise<CleanupAfterBackupResult> {
  const store = useBackupSessionStore.getState();
  if (!store.session.permissionSummary.removeAfterBackupEnabled) {
    return { kind: 'skipped' };
  }
  if (successfullyTransferredAssetIds.length === 0) {
    return { kind: 'skipped' };
  }
  try {
    const removedCount = await deps.media_library_gateway.delete_assets(successfullyTransferredAssetIds);
    return { kind: 'removed', removedCount };
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to remove transferred media.';
    return { kind: 'failed', message };
  }
}
