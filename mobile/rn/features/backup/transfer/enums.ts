export enum TransferTransport {
  Lan = 'lan',
  Usb = 'usb',
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
