import { NativeModules, Platform } from 'react-native';

describe('AndroidBatteryOptimizationGateway', () => {
  afterEach(() => {
    jest.resetModules();
    Platform.OS = 'ios';
    delete NativeModules.BackupTransferServiceModule;
  });

  it('delegates the exemption check to the native module on Android', async () => {
    Platform.OS = 'android';
    NativeModules.BackupTransferServiceModule = {
      isIgnoringBatteryOptimizations: jest.fn().mockResolvedValue(false),
      requestIgnoreBatteryOptimizations: jest.fn().mockResolvedValue(true),
    };

    const { AndroidBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
    const gateway = new AndroidBatteryOptimizationGateway();

    await expect(gateway.is_ignoring_battery_optimizations()).resolves.toBe(false);
    expect(NativeModules.BackupTransferServiceModule.isIgnoringBatteryOptimizations).toHaveBeenCalledTimes(1);
  });

  it('requests the exemption through the native module on Android', async () => {
    Platform.OS = 'android';
    NativeModules.BackupTransferServiceModule = {
      isIgnoringBatteryOptimizations: jest.fn().mockResolvedValue(false),
      requestIgnoreBatteryOptimizations: jest.fn().mockResolvedValue(true),
    };

    const { AndroidBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
    const gateway = new AndroidBatteryOptimizationGateway();

    await gateway.request_battery_optimization_exemption();
    expect(NativeModules.BackupTransferServiceModule.requestIgnoreBatteryOptimizations).toHaveBeenCalledTimes(1);
  });

  it('treats the app as exempt when the native module is unavailable', async () => {
    Platform.OS = 'android';
    NativeModules.BackupTransferServiceModule = undefined;

    const { AndroidBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
    const gateway = new AndroidBatteryOptimizationGateway();

    await expect(gateway.is_ignoring_battery_optimizations()).resolves.toBe(true);
    await expect(gateway.request_battery_optimization_exemption()).resolves.toBeUndefined();
  });

  it('treats the app as exempt on non-Android platforms', async () => {
    Platform.OS = 'ios';
    NativeModules.BackupTransferServiceModule = {
      isIgnoringBatteryOptimizations: jest.fn().mockResolvedValue(false),
      requestIgnoreBatteryOptimizations: jest.fn().mockResolvedValue(true),
    };

    const { AndroidBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
    const gateway = new AndroidBatteryOptimizationGateway();

    await expect(gateway.is_ignoring_battery_optimizations()).resolves.toBe(true);
    expect(NativeModules.BackupTransferServiceModule.isIgnoringBatteryOptimizations).not.toHaveBeenCalled();
  });

  it('swallows native errors instead of failing preflight', async () => {
    Platform.OS = 'android';
    NativeModules.BackupTransferServiceModule = {
      isIgnoringBatteryOptimizations: jest.fn().mockRejectedValue(new Error('native down')),
      requestIgnoreBatteryOptimizations: jest.fn().mockRejectedValue(new Error('native down')),
    };

    const { AndroidBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
    const gateway = new AndroidBatteryOptimizationGateway();

    await expect(gateway.is_ignoring_battery_optimizations()).resolves.toBe(true);
    await expect(gateway.request_battery_optimization_exemption()).resolves.toBeUndefined();
  });

  it('does not hang when the native exemption request never settles', async () => {
    jest.useFakeTimers();
    try {
      Platform.OS = 'android';
      NativeModules.BackupTransferServiceModule = {
        isIgnoringBatteryOptimizations: jest.fn().mockResolvedValue(false),
        requestIgnoreBatteryOptimizations: jest.fn(() => new Promise(() => {})),
      };

      const { AndroidBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
      const gateway = new AndroidBatteryOptimizationGateway();

      const promise = gateway.request_battery_optimization_exemption();
      jest.advanceTimersByTime(60_000);
      await expect(promise).resolves.toBeUndefined();
    } finally {
      jest.useRealTimers();
    }
  });

  it('always exempts on UnsupportedBatteryOptimizationGateway', async () => {
    const { UnsupportedBatteryOptimizationGateway } = require('@/infrastructure/system/battery-optimization-gateway');
    const gateway = new UnsupportedBatteryOptimizationGateway();

    await expect(gateway.is_ignoring_battery_optimizations()).resolves.toBe(true);
    await expect(gateway.request_battery_optimization_exemption()).resolves.toBeUndefined();
  });
});
