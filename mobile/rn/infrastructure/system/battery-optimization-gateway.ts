import { NativeModules, Platform } from 'react-native';

/**
 * Gateway for Android battery optimization (Doze / app standby) exemption.
 *
 * Without an exemption the OS can freeze the transfer process while the screen
 * is locked, even though a foreground service and a wake lock are held — the
 * transfer then only resumes after the user unlocks the device. Requesting the
 * exemption (ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) keeps the process
 * running long enough for a background USB backup to finish.
 */
export interface BatteryOptimizationGateway {
  is_ignoring_battery_optimizations(): Promise<boolean>;
  request_battery_optimization_exemption(): Promise<void>;
}

interface BatteryOptimizationNativeModule {
  isIgnoringBatteryOptimizations(): Promise<boolean>;
  requestIgnoreBatteryOptimizations(): Promise<boolean>;
}

const battery_optimization_native_module = NativeModules.BackupTransferServiceModule as
  | BatteryOptimizationNativeModule
  | undefined;

/**
 * Fallback if the native request promise never settles (e.g. the host resume
 * lifecycle event is not observed). Long enough for the user to respond to the
 * system dialog; preflight must not hang forever if it is missed.
 */
const EXEMPTION_REQUEST_TIMEOUT_MS = 60_000;

function with_timeout<T>(promise: Promise<T>, timeout_ms: number): Promise<T> {
  return new Promise<T>((resolve) => {
    const timer = setTimeout(() => resolve(undefined as T), timeout_ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      () => {
        clearTimeout(timer);
        resolve(undefined as T);
      }
    );
  });
}

export class AndroidBatteryOptimizationGateway implements BatteryOptimizationGateway {
  async is_ignoring_battery_optimizations(): Promise<boolean> {
    if (Platform.OS !== 'android' || battery_optimization_native_module == null) {
      return true;
    }
    try {
      return await battery_optimization_native_module.isIgnoringBatteryOptimizations();
    } catch {
      // Treat a failed check as exempt so the transfer is not blocked.
      return true;
    }
  }

  async request_battery_optimization_exemption(): Promise<void> {
    if (Platform.OS !== 'android' || battery_optimization_native_module == null) {
      return;
    }
    try {
      await with_timeout(
        battery_optimization_native_module.requestIgnoreBatteryOptimizations(),
        EXEMPTION_REQUEST_TIMEOUT_MS
      );
    } catch {
      // If the request cannot be shown, the transfer continues without exemption.
    }
  }
}

/** Platform/test default that treats the app as always exempt. */
export class UnsupportedBatteryOptimizationGateway implements BatteryOptimizationGateway {
  async is_ignoring_battery_optimizations(): Promise<boolean> {
    return true;
  }

  async request_battery_optimization_exemption(): Promise<void> {
    return;
  }
}
