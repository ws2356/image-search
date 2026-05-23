import { create } from 'zustand';

import type {
  BackupSessionState,
  LocalDeviceIdentitySummary,
} from '@/features/backup/session/models';
import { DEFAULT_HOME_SUMMARY } from '@/features/backup/session/models';
import type { BackupRoutePhase } from '@/features/backup/domain/route-phase';
import type { PairingSessionSummary, TrustedDesktopSummary } from '@/features/backup/pairing/models';
import {
  DEFAULT_PERMISSION_SUMMARY,
  type PermissionSummary,
} from '@/features/backup/preflight/models';
import type { ErrorSummary } from '@/features/backup/shared/models';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';

interface BackupSessionStoreState {
  session: BackupSessionState;
  setRoutePhase: (routePhase: BackupRoutePhase) => void;
  setPermissionSummary: (summary: PermissionSummary) => void;
  setPairingSession: (session: PairingSessionSummary | null) => void;
  setTrustedDesktop: (desktop: TrustedDesktopSummary | null) => void;
  setLocalDeviceIdentity: (identity: LocalDeviceIdentitySummary | null) => void;
  setTransferSnapshot: (snapshot: TransferProgressSnapshot | null) => void;
  setLatestError: (error: ErrorSummary | null) => void;
  resetSession: () => void;
}

const INITIAL_BACKUP_SESSION_STATE: BackupSessionState = {
  routePhase: 'home',
  homeSummary: DEFAULT_HOME_SUMMARY,
  permissionSummary: DEFAULT_PERMISSION_SUMMARY,
  pairingSession: null,
  trustedDesktop: null,
  localDeviceIdentity: null,
  transferSnapshot: null,
  latestError: null,
};

export const useBackupSessionStore = create<BackupSessionStoreState>((set) => ({
  session: INITIAL_BACKUP_SESSION_STATE,
  setRoutePhase: (routePhase) =>
    set((state) => ({
      session: {
        ...state.session,
        routePhase,
      },
    })),
  setPermissionSummary: (summary) =>
    set((state) => ({
      session: {
        ...state.session,
        permissionSummary: summary,
      },
    })),
  setPairingSession: (session) =>
    set((state) => ({
      session: {
        ...state.session,
        pairingSession: session,
      },
    })),
  setTrustedDesktop: (desktop) =>
    set((state) => ({
      session: {
        ...state.session,
        trustedDesktop: desktop,
      },
    })),
  setLocalDeviceIdentity: (identity) =>
    set((state) => ({
      session: {
        ...state.session,
        localDeviceIdentity: identity,
      },
    })),
  setTransferSnapshot: (snapshot) =>
    set((state) => ({
      session: {
        ...state.session,
        transferSnapshot: snapshot,
      },
    })),
  setLatestError: (error) =>
    set((state) => ({
      session: {
        ...state.session,
        latestError: error,
      },
    })),
  resetSession: () =>
    set({
      session: INITIAL_BACKUP_SESSION_STATE,
    }),
}));
