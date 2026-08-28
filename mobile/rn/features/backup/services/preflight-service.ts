import { PermissionScope } from '@/features/backup/preflight/enums';
import type { PermissionSummary } from '@/features/backup/preflight/models';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import {
  ExpoBatteryStatusGateway,
  type BatteryStatusGateway,
} from '@/infrastructure/system/battery-status-gateway';
import {
  AndroidBatteryOptimizationGateway,
  type BatteryOptimizationGateway,
  UnsupportedBatteryOptimizationGateway,
} from '@/infrastructure/system/battery-optimization-gateway';
import {
  ExpoMediaLibraryPermissionGateway,
  type PermissionGateway,
} from '@/infrastructure/system/permission-gateway';
import { Platform } from 'react-native';

export interface PreflightService {
  load_permission_summary(): Promise<PermissionSummary>;
  request_media_access(): Promise<PermissionScope>;
  set_remove_after_backup_enabled(enabled: boolean): Promise<void>;
  is_ignoring_battery_optimizations(): Promise<boolean>;
  request_battery_optimization_exemption(): Promise<void>;
}

export interface PreflightServiceDeps {
  permission_gateway: PermissionGateway;
  battery_status_gateway: BatteryStatusGateway;
  battery_optimization_gateway: BatteryOptimizationGateway;
  low_battery_threshold_percent: number;
}

const DEFAULT_LOW_BATTERY_THRESHOLD_PERCENT = 25;

function to_permission_scope(value: 'full' | 'limited' | 'denied'): PermissionScope {
  switch (value) {
    case 'full':
      return PermissionScope.Full;
    case 'limited':
      return PermissionScope.Limited;
    case 'denied':
      return PermissionScope.Denied;
    default: {
      const exhaustive_check: never = value;
      throw new Error(`Unsupported permission scope: ${exhaustive_check}`);
    }
  }
}

export class DefaultPreflightService implements PreflightService {
  private readonly permission_gateway: PermissionGateway;
  private readonly battery_status_gateway: BatteryStatusGateway;
  private readonly battery_optimization_gateway: BatteryOptimizationGateway;
  private readonly low_battery_threshold_percent: number;

  constructor(deps: PreflightServiceDeps) {
    this.permission_gateway = deps.permission_gateway;
    this.battery_status_gateway = deps.battery_status_gateway;
    this.battery_optimization_gateway = deps.battery_optimization_gateway;
    this.low_battery_threshold_percent = deps.low_battery_threshold_percent;
  }

  async load_permission_summary(): Promise<PermissionSummary> {
    const [media_scope, battery] = await Promise.all([
      this.permission_gateway.get_media_permission_scope(),
      this.battery_status_gateway.get_current_snapshot(),
    ]);
    const store = useBackupSessionStore.getState();
    const remove_after_backup_enabled = store.session.permissionSummary.removeAfterBackupEnabled;
    const charging = battery.charging ?? false;
    const low_battery_warning_needed =
      battery.percentage !== null && battery.percentage <= this.low_battery_threshold_percent;

    return {
      mediaScope: to_permission_scope(media_scope),
      batteryPercentage: battery.percentage,
      isCharging: charging,
      lowBatteryWarningNeeded: low_battery_warning_needed,
      removeAfterBackupEnabled: remove_after_backup_enabled,
    };
  }

  async request_media_access(): Promise<PermissionScope> {
    const media_scope = await this.permission_gateway.request_media_permission_scope();
    return to_permission_scope(media_scope);
  }

  async set_remove_after_backup_enabled(enabled: boolean): Promise<void> {
    const store = useBackupSessionStore.getState();
    store.setPermissionSummary({
      ...store.session.permissionSummary,
      removeAfterBackupEnabled: enabled,
    });
  }

  async is_ignoring_battery_optimizations(): Promise<boolean> {
    return this.battery_optimization_gateway.is_ignoring_battery_optimizations();
  }

  async request_battery_optimization_exemption(): Promise<void> {
    await this.battery_optimization_gateway.request_battery_optimization_exemption();
  }
}

export function create_default_preflight_service(): PreflightService {
  return new DefaultPreflightService({
    permission_gateway: new ExpoMediaLibraryPermissionGateway(),
    battery_status_gateway: new ExpoBatteryStatusGateway(),
    battery_optimization_gateway:
      Platform.OS === 'android'
        ? new AndroidBatteryOptimizationGateway()
        : new UnsupportedBatteryOptimizationGateway(),
    low_battery_threshold_percent: DEFAULT_LOW_BATTERY_THRESHOLD_PERCENT,
  });
}
