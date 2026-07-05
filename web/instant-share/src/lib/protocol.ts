export type PayloadType = 'text' | 'link' | 'html' | 'file';

export interface ManifestFileEntry {
  index: number;
  type: 'text' | 'link' | 'html' | 'file';
  content_type: string;
  size_bytes?: number;
  filename?: string;
  content?: string;
}

export type ControlMessage =
  | { msg: 'auth'; opt_code: string }
  | { msg: 'auth_ok'; session_id: string; file_count: number; payload_type: PayloadType }
  | { msg: 'auth_error'; error: string }
  | { msg: 'manifest' }
  | { msg: 'manifest'; files: ManifestFileEntry[] }
  | { msg: 'download'; index: number }
  | { msg: 'file_start'; index: number; content_type: string; filename: string; size: number }
  | { msg: 'file_end'; index: number }
  | { msg: 'error'; code: 'expired' | 'not_found' | 'busy' | 'not_authorized'; message: string }
  | { msg: 'bye' };

export type WireEvent =
  | { kind: 'control'; message: ControlMessage }
  | { kind: 'binary'; buffer: ArrayBuffer };

const KNOWN_MSGS = new Set<string>([
  'auth', 'auth_ok', 'auth_error', 'manifest', 'download',
  'file_start', 'file_end', 'error', 'bye',
]);

export function encodeControl(message: ControlMessage): string {
  return JSON.stringify(message);
}

export function decodeWireEvent(data: string | ArrayBuffer): WireEvent | null {
  if (typeof data !== 'string') {
    return { kind: 'binary', buffer: data };
  }
  if (!data) return null;
  try {
    const parsed = JSON.parse(data) as { msg?: string };
    if (!parsed.msg || !KNOWN_MSGS.has(parsed.msg)) return null;
    return { kind: 'control', message: parsed as ControlMessage };
  } catch {
    return null;
  }
}
