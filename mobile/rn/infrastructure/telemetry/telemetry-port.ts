export type TelemetryAttributes = Record<string, string | number | boolean | null | undefined>;

export interface TelemetryPort {
  track_event(name: string, attributes?: TelemetryAttributes): Promise<void>;
  track_error(name: string, attributes?: TelemetryAttributes): Promise<void>;
}

export class NoopTelemetryPort implements TelemetryPort {
  async track_event(_name: string, _attributes?: TelemetryAttributes): Promise<void> {
    return;
  }

  async track_error(_name: string, _attributes?: TelemetryAttributes): Promise<void> {
    return;
  }
}
