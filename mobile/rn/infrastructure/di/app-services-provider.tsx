import type { ReactNode } from 'react';
import React from 'react';

import {
  createBackupFlowOrchestrator,
  type BackupFlowOrchestrator,
} from '@/features/backup/orchestration/backup-flow-orchestrator';

export type AppRuntimeMode = 'native-capable';

export interface AppServices {
  runtimeMode: AppRuntimeMode;
  backupFlowOrchestrator: BackupFlowOrchestrator;
}

const AppServicesContext = React.createContext<AppServices | null>(null);

function createAppServices(): AppServices {
  return {
    runtimeMode: 'native-capable',
    backupFlowOrchestrator: createBackupFlowOrchestrator(),
  };
}

export function AppServicesProvider({ children }: { children: ReactNode }) {
  const servicesRef = React.useRef<AppServices | null>(null);
  if (!servicesRef.current) {
    servicesRef.current = createAppServices();
  }
  return <AppServicesContext.Provider value={servicesRef.current}>{children}</AppServicesContext.Provider>;
}

export function useAppServices(): AppServices {
  const services = React.use(AppServicesContext);
  if (!services) {
    throw new Error('useAppServices must be used inside AppServicesProvider');
  }
  return services;
}
