export interface BatteryStatusSnapshot {
  percentage: number | null;
  charging: boolean | null;
}

export interface BatteryStatusGateway {
  get_current_snapshot(): Promise<BatteryStatusSnapshot>;
}

export class StubBatteryStatusGateway implements BatteryStatusGateway {
  async get_current_snapshot(): Promise<BatteryStatusSnapshot> {
    return { percentage: null, charging: null };
  }
}

export class ExpoBatteryStatusGateway implements BatteryStatusGateway {
  async get_current_snapshot(): Promise<BatteryStatusSnapshot> {
    const battery = await import('expo-battery');
    const [level, state] = await Promise.all([
      battery.getBatteryLevelAsync(),
      battery.getBatteryStateAsync(),
    ]);
    const percentage = level >= 0 ? Math.round(level * 100) : null;
    const charging =
      state === battery.BatteryState.CHARGING || state === battery.BatteryState.FULL;
    return { percentage, charging };
  }
}
