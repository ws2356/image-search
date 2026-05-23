export interface AndroidTransferService {
  start_foreground_transfer_service(): Promise<void>;
  stop_foreground_transfer_service(): Promise<void>;
}

export class NoopAndroidTransferService implements AndroidTransferService {
  async start_foreground_transfer_service(): Promise<void> {
    return;
  }

  async stop_foreground_transfer_service(): Promise<void> {
    return;
  }
}
