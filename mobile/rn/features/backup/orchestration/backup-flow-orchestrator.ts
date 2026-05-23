import type { BackupCommand } from '@/features/backup/orchestration/backup-commands';
import { persist_pairing_success } from '@/features/backup/services/pairing-persistence-service';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';

export interface BackupFlowOrchestrator {
  execute: (command: BackupCommand) => Promise<void>;
  openScanFlow: () => Promise<void>;
  submitPairingPayload: (command: Extract<BackupCommand, { type: 'submitPairingPayload' }>) => Promise<void>;
  runPreflight: () => Promise<void>;
  startTransfer: () => Promise<void>;
  stopTransfer: () => Promise<void>;
  completeTransfer: () => Promise<void>;
  recoverFromError: () => Promise<void>;
  returnHome: () => Promise<void>;
}

async function openScanFlowImpl(): Promise<void> {
  const store = useBackupSessionStore.getState();
  store.setLatestError(null);
  store.setRoutePhase('scan');
}

async function submitPairingPayloadImpl(
  _command: Extract<BackupCommand, { type: 'submitPairingPayload' }>
): Promise<void> {
  useBackupSessionStore.getState().setRoutePhase('pair');
}

async function runPreflightImpl(): Promise<void> {
  useBackupSessionStore.getState().setRoutePhase('permissions');
}

async function startTransferImpl(): Promise<void> {
  useBackupSessionStore.getState().setRoutePhase('transfer');
}

async function stopTransferImpl(): Promise<void> {
  const store = useBackupSessionStore.getState();
  store.setLatestError({
    title: 'Transfer stopped',
    message: 'Transfer stop handling is defined in a later phase.',
  });
  store.setRoutePhase('error');
}

async function completeTransferImpl(): Promise<void> {
  useBackupSessionStore.getState().setRoutePhase('completed');
}

async function recoverFromErrorImpl(): Promise<void> {
  const store = useBackupSessionStore.getState();
  store.setLatestError(null);
  store.setRoutePhase('scan');
}

async function returnHomeImpl(): Promise<void> {
  const store = useBackupSessionStore.getState();
  store.resetSession();
  store.setRoutePhase('home');
}

async function executeImpl(command: BackupCommand): Promise<void> {
  const store = useBackupSessionStore.getState();

  switch (command.type) {
    case 'openScanFlow':
      return openScanFlowImpl();
    case 'submitPairingPayload':
      return submitPairingPayloadImpl(command);
    case 'pairingCompleted':
      {
        const persisted = await persist_pairing_success(command.session, store.session.localDeviceIdentity);
        store.setTrustedDesktop(persisted.trusted_desktop);
        store.setLocalDeviceIdentity(persisted.local_device_identity);
      }
      store.setPairingSession(command.session);
      store.setRoutePhase('permissions');
      return;
    case 'pairingFailed':
      store.setLatestError(command.error);
      store.setRoutePhase('error');
      return;
    case 'runPreflight':
      return runPreflightImpl();
    case 'preflightResolved':
      if (command.result.kind === 'success') {
        store.setRoutePhase('transfer');
        return;
      }
      store.setLatestError(command.result.error);
      store.setRoutePhase('error');
      return;
    case 'startTransfer':
      return startTransferImpl();
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
      return stopTransferImpl();
    case 'completeTransfer':
      return completeTransferImpl();
    case 'recoverFromError':
      return recoverFromErrorImpl();
    case 'returnHome':
      return returnHomeImpl();
    default: {
      const exhaustiveCheck: never = command;
      throw new Error(`Unsupported command: ${JSON.stringify(exhaustiveCheck)}`);
    }
  }
}

export function createBackupFlowOrchestrator(): BackupFlowOrchestrator {
  return {
    execute: executeImpl,
    openScanFlow: openScanFlowImpl,
    submitPairingPayload: submitPairingPayloadImpl,
    runPreflight: runPreflightImpl,
    startTransfer: startTransferImpl,
    stopTransfer: stopTransferImpl,
    completeTransfer: completeTransferImpl,
    recoverFromError: recoverFromErrorImpl,
    returnHome: returnHomeImpl,
  };
}
