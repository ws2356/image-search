import { log } from './log';

export interface ParsedShareParams {
  sessionId: string;
  optCode: string;
}

export function parseShareUrlParams(rawSearch: string): ParsedShareParams | null {
  const search = rawSearch.startsWith('?') ? rawSearch.slice(1) : rawSearch;
  if (!search) {
    log.warn('parseShareUrlParams: empty search string');
    return null;
  }
  const params = new URLSearchParams(search);
  const sessionId = params.get('sid') ?? '';
  const optCode = params.get('opt') ?? '';
  if (!sessionId || !optCode) {
    log.warn('parseShareUrlParams: missing sid or opt', { hasSid: !!sessionId, hasOpt: !!optCode, rawSearch });
    return null;
  }
  log.info('parseShareUrlParams: ok', { sessionId: sessionId.slice(0, 8) + '…', optCode: '***' });
  return { sessionId, optCode };
}
