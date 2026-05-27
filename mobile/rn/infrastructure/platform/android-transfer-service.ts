import { NativeEventEmitter, NativeModules, Platform } from 'react-native';
import type { PairingSessionSummary } from '@/features/backup/pairing/models';
import type { LocalDeviceIdentitySummary } from '@/features/backup/session/models';
import type { TransferProgressSnapshot } from '@/features/backup/transfer/models';

export interface AndroidTransferService {
  start_foreground_transfer_service(): Promise<void>;
  stop_foreground_transfer_service(): Promise<void>;
}

export interface AndroidHeadlessTransferTaskPayload {
  pairingSession: PairingSessionSummary;
  localDeviceIdentity: LocalDeviceIdentitySummary;
}

export type AndroidTransferSessionStatus = 'idle' | 'running' | 'completed' | 'failed' | 'stopped';

export interface AndroidTransferSessionState {
  status: AndroidTransferSessionStatus;
  snapshot: TransferProgressSnapshot | null;
  errorMessage: string | null;
}

interface AndroidTransferServiceNativeModule {
  startHeadlessTransferSession(taskPayloadJson: string): Promise<void>;
  requestStopTransferSession(): Promise<void>;
  publishProgress(snapshotJson: string): Promise<void>;
  publishState(stateJson: string): Promise<void>;
  getCurrentState(): Promise<{
    snapshotJson?: string | null;
    stateJson?: string | null;
  } | null>;
  clearState(): Promise<void>;
  clearStopRequested(): Promise<void>;
  isStopRequested(): boolean;
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

const TRANSFER_SERVICE_STATE_EVENT = 'BackupTransferServiceStateChanged';
const android_transfer_service_native_module = NativeModules.BackupTransferServiceModule as
  | AndroidTransferServiceNativeModule
  | undefined;
const android_transfer_service_event_emitter =
  Platform.OS === 'android' && android_transfer_service_native_module
    ? new NativeEventEmitter(android_transfer_service_native_module)
    : null;

function parse_transfer_state_payload(payload: {
  snapshotJson?: string | null;
  stateJson?: string | null;
} | null): AndroidTransferSessionState | null {
  if (payload == null) {
    return null;
  }
  const parsed_state =
    payload.stateJson != null
      ? JSON.parse(payload.stateJson) as Partial<Pick<AndroidTransferSessionState, 'status' | 'errorMessage'>>
      : null;
  const parsed_snapshot =
    payload.snapshotJson != null
      ? JSON.parse(payload.snapshotJson) as TransferProgressSnapshot
      : null;

  return {
    status: parsed_state?.status ?? 'idle',
    snapshot: parsed_snapshot,
    errorMessage: parsed_state?.errorMessage ?? null,
  };
}

function require_android_transfer_service_native_module(): AndroidTransferServiceNativeModule {
  if (!android_transfer_service_native_module || Platform.OS !== 'android') {
    throw new Error('Android foreground transfer service is unavailable on this platform.');
  }
  return android_transfer_service_native_module;
}

export function is_android_headless_transfer_supported(): boolean {
  return Platform.OS === 'android' && android_transfer_service_native_module != null;
}

export async function start_android_headless_transfer_session(
  payload: AndroidHeadlessTransferTaskPayload
): Promise<void> {
  await require_android_transfer_service_native_module().startHeadlessTransferSession(JSON.stringify(payload));
}

export async function request_stop_android_headless_transfer_session(): Promise<void> {
  await require_android_transfer_service_native_module().requestStopTransferSession();
}

export async function publish_android_transfer_progress(snapshot: TransferProgressSnapshot): Promise<void> {
  await require_android_transfer_service_native_module().publishProgress(JSON.stringify(snapshot));
}

export async function publish_android_transfer_state(input: {
  status: Exclude<AndroidTransferSessionStatus, 'idle'>;
  errorMessage?: string | null;
}): Promise<void> {
  await require_android_transfer_service_native_module().publishState(
    JSON.stringify({
      status: input.status,
      errorMessage: input.errorMessage ?? null,
    })
  );
}

export async function get_current_android_transfer_session_state(): Promise<AndroidTransferSessionState | null> {
  const payload = await require_android_transfer_service_native_module().getCurrentState();
  return parse_transfer_state_payload(payload);
}

export async function clear_android_transfer_stop_request(): Promise<void> {
  await require_android_transfer_service_native_module().clearStopRequested();
}

export async function clear_android_transfer_session_state(): Promise<void> {
  await require_android_transfer_service_native_module().clearState();
}

export function is_android_transfer_stop_requested(): boolean {
  if (!is_android_headless_transfer_supported()) {
    return false;
  }
  return require_android_transfer_service_native_module().isStopRequested();
}

export function add_android_transfer_session_listener(
  listener: (state: AndroidTransferSessionState | null) => void
): { remove: () => void } {
  if (!android_transfer_service_event_emitter) {
    return { remove: () => undefined };
  }
  const subscription = android_transfer_service_event_emitter.addListener(
    TRANSFER_SERVICE_STATE_EVENT,
    (payload: { snapshotJson?: string | null; stateJson?: string | null } | null) => {
      listener(parse_transfer_state_payload(payload));
    }
  );
  return {
    remove: () => {
      subscription.remove();
    },
  };
}

export class NoopAndroidTransferService implements AndroidTransferService {
  async start_foreground_transfer_service(): Promise<void> {
    return;
  }

  async stop_foreground_transfer_service(): Promise<void> {
    return;
  }
}
