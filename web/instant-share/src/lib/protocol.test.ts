import { describe, it, expect } from 'vitest';
import { encodeControl, decodeWireEvent } from './protocol';

describe('protocol codec', () => {
  it('encodes a control message as JSON string', () => {
    const s = encodeControl({ msg: 'auth', opt_code: '123456' });
    expect(s).toBe('{"msg":"auth","opt_code":"123456"}');
  });

  it('decodes a string control message', () => {
    const ev = decodeWireEvent('{"msg":"auth_ok","session_id":"s1","file_count":2,"payload_type":"file"}');
    expect(ev?.kind).toBe('control');
    expect(ev?.kind === 'control' && ev.message.msg).toBe('auth_ok');
  });

  it('decodes an ArrayBuffer as binary', () => {
    const buf = new Uint8Array([1, 2, 3]).buffer;
    const ev = decodeWireEvent(buf);
    expect(ev?.kind).toBe('binary');
    if (ev?.kind === 'binary') {
      expect(new Uint8Array(ev.buffer)).toEqual(new Uint8Array([1, 2, 3]));
    }
  });

  it('returns null for malformed JSON string', () => {
    expect(decodeWireEvent('not json')).toBeNull();
  });

  it('returns null for unknown msg field', () => {
    expect(decodeWireEvent('{"msg":"bogus"}')).toBeNull();
  });

  it('returns null for empty string', () => {
    expect(decodeWireEvent('')).toBeNull();
  });

  it('round-trips manifest with inline text content', () => {
    const manifest = {
      msg: 'manifest' as const,
      files: [{ index: 0, type: 'text' as const, content_type: 'text/plain', content: 'hi' }],
    };
    const s = encodeControl(manifest);
    const ev = decodeWireEvent(s);
    expect(ev?.kind).toBe('control');
    if (ev?.kind === 'control' && ev.message.msg === 'manifest') {
      const m = ev.message as { msg: 'manifest'; files: { index: number; content: string }[] };
      expect(m.files[0].content).toBe('hi');
    }
  });
});
