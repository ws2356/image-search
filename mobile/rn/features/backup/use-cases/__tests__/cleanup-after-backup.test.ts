import { PermissionScope } from '@/features/backup/preflight/enums';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import {
  cleanupAfterBackup,
  type CleanupAfterBackupDeps,
  type CleanupAfterBackupResult,
} from '@/features/backup/use-cases/cleanup-after-backup';

function setRemoveAfterBackupPreference(enabled: boolean): void {
  useBackupSessionStore.getState().setPermissionSummary({
    mediaScope: PermissionScope.Full,
    batteryPercentage: null,
    isCharging: false,
    lowBatteryWarningNeeded: false,
    removeAfterBackupEnabled: enabled,
  });
}

function makeDeps(delete_assets: jest.Mock): CleanupAfterBackupDeps {
  return {
    media_library_gateway: {
      enumerate_transfer_candidates: jest.fn(),
      open_asset_chunk_reader: jest.fn(),
      delete_assets,
    },
  };
}

beforeEach(() => {
  useBackupSessionStore.setState({
    session: {
      ...useBackupSessionStore.getState().session,
      permissionSummary: {
        mediaScope: PermissionScope.Full,
        batteryPercentage: null,
        isCharging: false,
        lowBatteryWarningNeeded: false,
        removeAfterBackupEnabled: false,
      },
    },
  });
});

test('cleanupAfterBackup skips deletion when the remove-after-backup preference is disabled', async () => {
  setRemoveAfterBackupPreference(false);
  const delete_assets = jest.fn().mockResolvedValue(2);
  const result = await cleanupAfterBackup(['a1', 'a2'], makeDeps(delete_assets));

  expect(result).toEqual<CleanupAfterBackupResult>({ kind: 'skipped' });
  expect(delete_assets).not.toHaveBeenCalled();
});

test('cleanupAfterBackup skips deletion when there are no transferred asset ids', async () => {
  setRemoveAfterBackupPreference(true);
  const delete_assets = jest.fn().mockResolvedValue(0);
  const result = await cleanupAfterBackup([], makeDeps(delete_assets));

  expect(result).toEqual<CleanupAfterBackupResult>({ kind: 'skipped' });
  expect(delete_assets).not.toHaveBeenCalled();
});

test('cleanupAfterBackup deletes only the provided transferred asset ids when enabled', async () => {
  setRemoveAfterBackupPreference(true);
  const delete_assets = jest.fn().mockResolvedValue(3);
  const result = await cleanupAfterBackup(['a1', 'a2', 'a3'], makeDeps(delete_assets));

  expect(result).toEqual<CleanupAfterBackupResult>({ kind: 'removed', removedCount: 3 });
  expect(delete_assets).toHaveBeenCalledTimes(1);
  expect(delete_assets).toHaveBeenCalledWith(['a1', 'a2', 'a3']);
});

test('cleanupAfterBackup reports a failure when deletion throws', async () => {
  setRemoveAfterBackupPreference(true);
  const delete_assets = jest.fn().mockRejectedValue(new Error('media store unavailable'));
  const result = await cleanupAfterBackup(['a1'], makeDeps(delete_assets));

  expect(result.kind).toBe('failed');
  if (result.kind === 'failed') {
    expect(result.message).toContain('media store unavailable');
  }
});
