export enum PermissionScope {
  Full = 'full',
  Limited = 'limited',
  Denied = 'denied',
}

export enum PreflightFailureReason {
  PermissionsCancelled = 'permissions-cancelled',
  LowBatteryDeclined = 'low-battery-declined',
  MissingMediaAccess = 'missing-media-access',
  Unknown = 'unknown',
}
