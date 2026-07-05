export interface ParsedShareParams {
  sessionId: string;
  optCode: string;
}

export function parseShareUrlParams(rawSearch: string): ParsedShareParams | null {
  const search = rawSearch.startsWith('?') ? rawSearch.slice(1) : rawSearch;
  if (!search) return null;
  const params = new URLSearchParams(search);
  const sessionId = params.get('sid') ?? '';
  const optCode = params.get('opt') ?? '';
  if (!sessionId || !optCode) return null;
  return { sessionId, optCode };
}
