import type { PairingQRCodePayload } from '@/features/backup/pairing/models';
import { decode_pairing_link } from '@/features/backup/services/pairing-link-decoder';
import { useBackupSessionStore } from '@/features/backup/store/backup-session-store';
import { useBackupUiStore } from '@/features/backup/store/backup-ui-store';
import { apply_backup_command } from '@/features/backup/state/backup-flow-transition-helper';

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

  const session = useBackupSessionStore.getState().session;
  const has_active_session = session.routePhase !== 'home' && session.pairingSession !== null;
  const should_prompt_replacement =
    has_active_session && session.pairingSession?.sessionId !== payload.sessionId;

  if (should_prompt_replacement) {
    useBackupUiStore.getState().showIncomingLinkReplacement({
      currentSessionId: session.pairingSession?.sessionId ?? null,
      incomingPayload: payload,
    });
    return { accepted: true, payload };
  }

  await apply_backup_command({ type: 'openScanFlow' });
  return { accepted: true, payload };
}
