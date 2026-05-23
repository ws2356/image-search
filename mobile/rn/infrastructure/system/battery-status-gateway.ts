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
