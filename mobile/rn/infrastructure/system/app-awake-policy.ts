export interface AppAwakePolicy {
  set_awake_enabled(enabled: boolean): Promise<void>;
}

export class NoopAppAwakePolicy implements AppAwakePolicy {
  async set_awake_enabled(_enabled: boolean): Promise<void> {
    return;
  }
}
