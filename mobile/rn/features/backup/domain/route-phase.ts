export const BACKUP_ROUTE_PHASES = [
  'home',
  'scan',
  'pair',
  'permissions',
  'transfer',
  'completed',
  'error',
] as const;

export type BackupRoutePhase = (typeof BACKUP_ROUTE_PHASES)[number];

export const TERMINAL_BACKUP_ROUTE_PHASES = ['completed', 'error'] as const;

export type TerminalBackupRoutePhase = (typeof TERMINAL_BACKUP_ROUTE_PHASES)[number];

export function isBackupRoutePhase(value: string): value is BackupRoutePhase {
  return (BACKUP_ROUTE_PHASES as readonly string[]).includes(value);
}

export function isTerminalBackupRoutePhase(
  value: BackupRoutePhase
): value is TerminalBackupRoutePhase {
  return (TERMINAL_BACKUP_ROUTE_PHASES as readonly string[]).includes(value);
}
