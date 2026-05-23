import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { decode_pairing_link } from '@/features/backup/services/pairing-link-decoder';
import { useBackupUiStore } from '@/features/backup/store/backup-ui-store';

export interface ProcessIncomingLinkResult {
  accepted: boolean;
  payload: PairingQRCodePayload | null;
}

export function parse_pairing_link_payload(link: string): PairingQRCodePayload | null {
  const decoded = decode_pairing_link(link);
  return decoded.ok ? decoded.payload : null;
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
