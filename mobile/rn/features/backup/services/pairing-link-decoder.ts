import type { PairingQRCodePayload } from '@/features/backup/pairing/models';

export interface PairingLinkDecodeSuccess {
  ok: true;
  payload: PairingQRCodePayload;
}

export interface PairingLinkDecodeFailure {
  ok: false;
  message: string;
}

export type PairingLinkDecodeResult = PairingLinkDecodeSuccess | PairingLinkDecodeFailure;

function parse_required_query_param(url: URL, key: 'v' | 'ept' | 'sid' | 'opt' | 'usp'): string | null {
  const value = url.searchParams.get(key)?.trim();
  return value && value.length > 0 ? value : null;
}

function parse_fragment_search_params(url: URL): URLSearchParams {
  const raw_hash = url.hash.startsWith('#') ? url.hash.slice(1) : url.hash;
  const fragment_query = raw_hash.includes('?') ? raw_hash.split('?').pop() ?? '' : raw_hash;
  return new URLSearchParams(fragment_query);
}

export function decode_pairing_link(link: string): PairingLinkDecodeResult {
  let parsed: URL;
  try {
    parsed = new URL(link);
  } catch {
    return { ok: false, message: 'Link is not a valid URL.' };
  }

  const version = parse_required_query_param(parsed, 'v');
  const endpoint_targets_raw = parse_required_query_param(parsed, 'ept');
  const session_id = parse_required_query_param(parsed, 'sid');
  const fragment_search_params = parse_fragment_search_params(parsed);
  const fragment_opt = fragment_search_params.get('opt')?.trim();
  const query_opt = parse_required_query_param(parsed, 'opt');
  const one_time_passcode = fragment_opt && fragment_opt.length > 0 ? fragment_opt : query_opt;
  const suggested_usb_port_raw = parse_required_query_param(parsed, 'usp');
  const strict_security = parsed.searchParams.get('sec')?.trim();
  if (!version || !endpoint_targets_raw || !session_id || !one_time_passcode || !suggested_usb_port_raw) {
    return { ok: false, message: 'Link is missing required query params v,ept,sid,opt,usp.' };
  }

  const schema_version = Number.parseInt(version, 10);
  if (Number.isNaN(schema_version)) {
    return { ok: false, message: 'Link field v must be an integer.' };
  }

  const suggested_usb_port = Number.parseInt(suggested_usb_port_raw, 10);
  if (Number.isNaN(suggested_usb_port)) {
    return { ok: false, message: 'Link field usp must be an integer.' };
  }

  const endpoint_targets = endpoint_targets_raw
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  if (endpoint_targets.length === 0) {
    return { ok: false, message: 'Link field ept must contain at least one endpoint target.' };
  }

  return {
    ok: true,
    payload: {
      schemaVersion: schema_version,
      endpointTargets: endpoint_targets,
      sessionId: session_id,
      oneTimePasscode: one_time_passcode,
      suggestedUsbPort: suggested_usb_port,
      strictSecurityEnabled: strict_security === '1',
    },
  };
}
