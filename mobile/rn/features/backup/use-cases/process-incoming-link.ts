import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { useBackupUiStore } from '@/features/backup/store/backup-ui-store';

export interface ProcessIncomingLinkResult {
  accepted: boolean;
  payload: PairingQRCodePayload | null;
}

export function parse_pairing_link_payload(link: string): PairingQRCodePayload | null {
  let parsed: URL;
  try {
    parsed = new URL(link);
  } catch {
    return null;
  }

  const sid = parsed.searchParams.get('sid')?.trim();
  const opt = parsed.searchParams.get('opt')?.trim();
  const ept = parsed.searchParams.get('ept')?.trim();
  const usp = parsed.searchParams.get('usp')?.trim();
  const version = parsed.searchParams.get('v')?.trim();
  const sec = parsed.searchParams.get('sec')?.trim();
  if (!sid || !opt || !ept || !usp || !version) {
    return null;
  }

  const suggested_usb_port = Number.parseInt(usp, 10);
  if (Number.isNaN(suggested_usb_port)) {
    return null;
  }

  return {
    schemaVersion: Number.parseInt(version, 10),
    endpointTargets: ept.split(',').map((value) => value.trim()).filter(Boolean),
    sessionId: sid,
    oneTimePasscode: opt,
    suggestedUsbPort: suggested_usb_port,
    strictSecurityEnabled: sec === '1',
  };
}

export async function processIncomingLink(link: string): Promise<ProcessIncomingLinkResult> {
  const payload = parse_pairing_link_payload(link);
  if (!payload) {
    return { accepted: false, payload: null };
  }

  useBackupUiStore.getState().showIncomingLinkReplacement({
    currentSessionId: payload.sessionId,
    incomingPayload: payload,
  });
  return { accepted: true, payload };
}
