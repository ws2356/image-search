export enum PermissionScope {
  Full = 'full',
  Limited = 'limited',
  Denied = 'denied',
}

export enum TransferTransport {
  Lan = 'lan',
  Usb = 'usb',
}

export enum PairingFailureReason {
  Cancelled = 'cancelled',
  Rejected = 'rejected',
  Expired = 'expired',
  InvalidPayload = 'invalid-payload',
  Network = 'network',
  Unknown = 'unknown',
}

export enum PreflightFailureReason {
  PermissionsCancelled = 'permissions-cancelled',
  LowBatteryDeclined = 'low-battery-declined',
  MissingMediaAccess = 'missing-media-access',
  Unknown = 'unknown',
}

export enum TransferFailureReason {
  StopConfirmed = 'stop-confirmed',
  DesktopUnreachable = 'desktop-unreachable',
  WifiLost = 'wifi-lost',
  ReconnectRequired = 'reconnect-required',
  Unknown = 'unknown',
}

export enum TransferPipelineStage {
  Enumerating = 'enumerating',
  ExistingCheck = 'existing-check',
  Transferring = 'transferring',
  Completing = 'completing',
}
