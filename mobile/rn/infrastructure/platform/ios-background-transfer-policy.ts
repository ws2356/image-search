export interface IosBackgroundTransferPolicy {
  begin_transfer_session(): Promise<void>;
  end_transfer_session(): Promise<void>;
}

export class NoopIosBackgroundTransferPolicy implements IosBackgroundTransferPolicy {
  async begin_transfer_session(): Promise<void> {
    return;
  }

  async end_transfer_session(): Promise<void> {
    return;
  }
}
