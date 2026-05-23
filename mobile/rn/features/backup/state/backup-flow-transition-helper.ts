import type { BackupCommand } from '@/features/backup/orchestration/backup-commands';
import { persist_pairing_success } from '@/features/backup/services/pairing-persistence-service';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';

export async function apply_backup_command(command: BackupCommand): Promise<void> {
  const store = useBackupSessionStore.getState();

  switch (command.type) {
    case 'openScanFlow':
      store.setLatestError(null);
      store.setRoutePhase('scan');
      return;
    case 'submitPairingPayload':
      store.setRoutePhase('pair');
      return;
    case 'pairingCompleted': {
      const persisted = await persist_pairing_success(command.session, store.session.localDeviceIdentity);
      store.setTrustedDesktop(persisted.trusted_desktop);
      store.setLocalDeviceIdentity(persisted.local_device_identity);
      store.setPairingSession(command.session);
      store.setRoutePhase('permissions');
      return;
    }
    case 'pairingFailed':
      store.setLatestError(command.error);
      store.setRoutePhase('error');
      return;
    case 'runPreflight':
      store.setRoutePhase('permissions');
      return;
    case 'preflightResolved':
      if (command.result.kind === 'success') {
        store.setRoutePhase('transfer');
        return;
      }
      store.setLatestError(command.result.error);
      store.setRoutePhase('error');
      return;
    case 'startTransfer':
      store.setRoutePhase('transfer');
      return;
    case 'transferSnapshotUpdated':
      store.setTransferSnapshot(command.snapshot);
      return;
    case 'transferResolved':
      if (command.result.kind === 'success') {
        store.setRoutePhase('completed');
        return;
      }
      store.setLatestError(command.result.error);
      store.setRoutePhase('error');
      return;
    case 'stopTransfer':
      store.setLatestError({
        title: 'Transfer stopped',
        message: 'Transfer stop handling is defined in a later phase.',
      });
      store.setRoutePhase('error');
      return;
    case 'completeTransfer':
      store.setRoutePhase('completed');
      return;
    case 'recoverFromError':
      store.setLatestError(null);
      store.setRoutePhase('scan');
      return;
    case 'returnHome':
      store.resetSession();
      store.setRoutePhase('home');
      return;
    default: {
      const exhaustive_check: never = command;
      throw new Error(`Unsupported command: ${JSON.stringify(exhaustive_check)}`);
    }
  }
}
