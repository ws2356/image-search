import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { isWeChatWebview } from './env';

describe('isWeChatWebview', () => {
  const originalUserAgent = navigator.userAgent;

  afterEach(() => {
    Object.defineProperty(navigator, 'userAgent', {
      value: originalUserAgent,
      configurable: true,
    });
  });

  beforeEach(() => {
    Object.defineProperty(navigator, 'userAgent', {
      value: 'Mozilla/5.0 (iPhone) AppleWebKit/605.1.15',
      configurable: true,
    });
  });

  it('returns false for a normal browser', () => {
    expect(isWeChatWebview()).toBe(false);
  });

  it('returns true for a WeChat webview', () => {
    Object.defineProperty(navigator, 'userAgent', {
      value: 'Mozilla/5.0 MicroMessenger/8.0 Safari/605',
      configurable: true,
    });
    expect(isWeChatWebview()).toBe(true);
  });

  it('is case-insensitive', () => {
    Object.defineProperty(navigator, 'userAgent', {
      value: 'Mozilla/5.0 micromessenger/8.0 Safari/605',
      configurable: true,
    });
    expect(isWeChatWebview()).toBe(true);
  });
});
