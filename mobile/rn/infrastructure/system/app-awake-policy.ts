import { Platform } from 'react-native';

export interface AppAwakePolicy {
  set_awake_enabled(enabled: boolean): Promise<void>;
}

export class NoopAppAwakePolicy implements AppAwakePolicy {
  async set_awake_enabled(_enabled: boolean): Promise<void> {
    return;
  }
}

export class AndroidKeepAwakePolicy implements AppAwakePolicy {
  async set_awake_enabled(enabled: boolean): Promise<void> {
    const keep_awake = await import('expo-keep-awake');
    if (enabled) {
      await keep_awake.activateKeepAwakeAsync('aubackup-transfer');
      return;
    }
    await keep_awake.deactivateKeepAwake('aubackup-transfer');
  }
}

export class IosStubAppAwakePolicy implements AppAwakePolicy {
  async set_awake_enabled(_enabled: boolean): Promise<void> {
    return;
  }
}

export function create_default_app_awake_policy(): AppAwakePolicy {
  if (Platform.OS === 'android') {
    return new AndroidKeepAwakePolicy();
  }
  if (Platform.OS === 'ios') {
    return new IosStubAppAwakePolicy();
  }
  return new NoopAppAwakePolicy();
}
