import AsyncStorage from '@react-native-async-storage/async-storage';
import type { PairingSessionSummary, TrustedDesktopSummary } from '@/features/backup/pairing/models';
import { DEFAULT_HOME_SUMMARY, type HomeSummary, type LocalDeviceIdentitySummary } from '@/features/backup/session/models';
import {
  AsyncStorageLocalDeviceIdentityRepository,
  type LocalDeviceIdentityRecord,
} from '@/infrastructure/storage/local-device-identity-repository';
import {
  AsyncStorageTrustedDesktopRepository,
  type TrustedDesktopRecord,
} from '@/infrastructure/storage/trusted-desktop-repository';

const trusted_desktop_repository = new AsyncStorageTrustedDesktopRepository();
const local_device_identity_repository = new AsyncStorageLocalDeviceIdentityRepository();
const HOME_SUMMARY_STORAGE_KEY = 'backup.homeSummary';

export interface PairingPersistenceResult {
  trusted_desktop: TrustedDesktopSummary;
  local_device_identity: LocalDeviceIdentitySummary;
}

export interface PersistedPairingState {
  trusted_desktop: TrustedDesktopSummary | null;
  local_device_identity: LocalDeviceIdentitySummary | null;
  home_summary: HomeSummary | null;
}

function is_home_summary(value: unknown): value is HomeSummary {
  if (typeof value !== 'object' || value == null) {
    return false;
  }
  const candidate = value as Partial<HomeSummary>;
  return (
    (candidate.desktopName == null || typeof candidate.desktopName === 'string') &&
    (candidate.lastBackupDescription == null || typeof candidate.lastBackupDescription === 'string') &&
    typeof candidate.permissionScope === 'string' &&
    (candidate.interruptionWarning == null || typeof candidate.interruptionWarning === 'string')
  );
}

function to_trusted_desktop_summary(record: TrustedDesktopRecord): TrustedDesktopSummary {
  return {
    desktopId: record.desktop_id,
    desktopName: record.desktop_name,
    claimedAt: record.claimed_at,
    endpointBaseUrls: record.endpoint_base_urls,
    lastSuccessfulSessionId: record.last_successful_session_id ?? null,
  };
}

function to_local_device_identity_summary(record: LocalDeviceIdentityRecord): LocalDeviceIdentitySummary {
  return {
    deviceUuid: record.device_uuid,
    deviceName: record.device_name,
    platform: record.platform,
    updatedAt: record.updated_at,
  };
}

export async function persist_pairing_success(
  session: PairingSessionSummary,
  current_identity: LocalDeviceIdentitySummary | null
): Promise<PairingPersistenceResult> {
  const now = new Date().toISOString();
  const desktop_id = session.sessionId ?? `desktop-${Date.now()}`;
  const endpoint_url = session.endpointBaseUrl;
  const trusted_record: TrustedDesktopRecord = {
    desktop_id,
    desktop_name: session.desktopName ?? 'Desktop',
    endpoint_base_urls: endpoint_url ? [endpoint_url] : [],
    claimed_at: session.pairingCompletedAt ?? now,
    last_successful_session_id: session.sessionId ?? undefined,
  };
  await trusted_desktop_repository.upsert(trusted_record);

  const local_record: LocalDeviceIdentityRecord = current_identity
    ? {
        device_uuid: current_identity.deviceUuid,
        device_name: current_identity.deviceName,
        platform: current_identity.platform,
        updated_at: now,
      }
    : {
        device_uuid: `mobile-${desktop_id}`,
        device_name: 'Mobile Device',
        platform: 'android',
        updated_at: now,
      };
  await local_device_identity_repository.upsert(local_record);

  return {
    trusted_desktop: to_trusted_desktop_summary(trusted_record),
    local_device_identity: to_local_device_identity_summary(local_record),
  };
}

export async function load_persisted_pairing_state(): Promise<PersistedPairingState> {
  const [trusted_desktop, local_device_identity, home_summary] = await Promise.all([
    trusted_desktop_repository.get_latest(),
    local_device_identity_repository.get_current(),
    AsyncStorage.getItem(HOME_SUMMARY_STORAGE_KEY),
  ]);
  const parsed_home_summary: HomeSummary | null =
    home_summary == null ? null : JSON.parse(home_summary) as HomeSummary;
  if (parsed_home_summary != null && !is_home_summary(parsed_home_summary)) {
    throw new Error('Persisted home summary data is invalid.');
  }

  return {
    trusted_desktop: trusted_desktop ? to_trusted_desktop_summary(trusted_desktop) : null,
    local_device_identity: local_device_identity ? to_local_device_identity_summary(local_device_identity) : null,
    home_summary: parsed_home_summary ? { ...DEFAULT_HOME_SUMMARY, ...parsed_home_summary } : null,
  };
}

export async function persist_home_summary(summary: HomeSummary): Promise<void> {
  await AsyncStorage.setItem(HOME_SUMMARY_STORAGE_KEY, JSON.stringify(summary));
}
