import { describe, it, expect } from 'vitest';
import { parseShareUrlParams } from './urlParams';

describe('parseShareUrlParams', () => {
  it('parses sid and opt from a full QR URL search string', () => {
    const search = '?ips=192.168.1.5&p=9527&sp=9528&sid=abc-123&opt=123456';
    expect(parseShareUrlParams(search)).toEqual({
      sessionId: 'abc-123',
      optCode: '123456',
    });
  });

  it('ignores ips/p/sp fields but still returns sid/opt', () => {
    const search = '?sid=xyz&opt=999999';
    const result = parseShareUrlParams(search);
    expect(result?.sessionId).toBe('xyz');
    expect(result?.optCode).toBe('999999');
  });

  it('returns null when sid is missing', () => {
    expect(parseShareUrlParams('?opt=123456')).toBeNull();
  });

  it('returns null when opt is missing', () => {
    expect(parseShareUrlParams('?sid=abc')).toBeNull();
  });

  it('returns null when both are empty', () => {
    expect(parseShareUrlParams('?sid=&opt=')).toBeNull();
  });

  it('returns null for empty input', () => {
    expect(parseShareUrlParams('')).toBeNull();
  });

  it('handles leading ? prefix being absent', () => {
    expect(parseShareUrlParams('sid=abc&opt=123456')).toEqual({
      sessionId: 'abc',
      optCode: '123456',
    });
  });
});
