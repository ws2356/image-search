export enum BackupDomainErrorCode {
  InvalidRoutePhase = 'invalid-route-phase',
  InvalidPairingPayload = 'invalid-pairing-payload',
  PairingFailed = 'pairing-failed',
  PreflightFailed = 'preflight-failed',
  TransferFailed = 'transfer-failed',
  PersistenceFailed = 'persistence-failed',
  UnsupportedRuntime = 'unsupported-runtime',
}

export class BackupDomainError extends Error {
  public readonly code: BackupDomainErrorCode;
  public readonly causeValue: unknown;

  constructor(code: BackupDomainErrorCode, message: string, causeValue?: unknown) {
    super(message);
    this.name = 'BackupDomainError';
    this.code = code;
    this.causeValue = causeValue;
  }
}
