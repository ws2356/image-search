import type {
  AndroidTransferService,
} from '@/infrastructure/platform/android-transfer-service';
import { NoopAndroidTransferService } from '@/infrastructure/platform/android-transfer-service';
import type {
  IosBackgroundTransferPolicy,
} from '@/infrastructure/platform/ios-background-transfer-policy';
import { NoopIosBackgroundTransferPolicy } from '@/infrastructure/platform/ios-background-transfer-policy';
import { get_platform_capabilities, type PlatformCapabilities } from '@/infrastructure/platform/platform-capabilities';
import type { AppAwakePolicy } from '@/infrastructure/system/app-awake-policy';
import { NoopAppAwakePolicy } from '@/infrastructure/system/app-awake-policy';

export interface TransferRuntimeWiring {
  platform_capabilities: PlatformCapabilities;
  android_transfer_service: AndroidTransferService;
  ios_background_transfer_policy: IosBackgroundTransferPolicy;
  app_awake_policy: AppAwakePolicy;
}

const default_transfer_runtime_wiring: TransferRuntimeWiring = {
  platform_capabilities: get_platform_capabilities(),
  android_transfer_service: new NoopAndroidTransferService(),
  ios_background_transfer_policy: new NoopIosBackgroundTransferPolicy(),
  app_awake_policy: new NoopAppAwakePolicy(),
};

export function get_default_transfer_runtime_wiring(): TransferRuntimeWiring {
  return default_transfer_runtime_wiring;
}

export async function begin_transfer_runtime_session(wiring: TransferRuntimeWiring): Promise<void> {
  await wiring.app_awake_policy.set_awake_enabled(true);
  if (wiring.platform_capabilities.platform === 'android') {
    await wiring.android_transfer_service.start_foreground_transfer_service();
    return;
  }
  if (wiring.platform_capabilities.platform === 'ios') {
    await wiring.ios_background_transfer_policy.begin_transfer_session();
  }
}

export async function end_transfer_runtime_session(wiring: TransferRuntimeWiring): Promise<void> {
  await wiring.app_awake_policy.set_awake_enabled(false);
  if (wiring.platform_capabilities.platform === 'android') {
    await wiring.android_transfer_service.stop_foreground_transfer_service();
    return;
  }
  if (wiring.platform_capabilities.platform === 'ios') {
    await wiring.ios_background_transfer_policy.end_transfer_session();
  }
}
