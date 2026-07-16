import { describe, it, expect, vi } from 'vitest';
import { planDelivery, applyDelivery, type DeliveryAction } from './deliverer';
import type { ManifestFileEntry } from '../lib/protocol';

const mkEntry = (over: Partial<ManifestFileEntry>): ManifestFileEntry => ({
  index: 0,
  type: 'file',
  content_type: 'application/octet-stream',
  ...over,
});

interface ShareMock { secure: boolean; share: boolean; canShare: boolean; shareImpl?: () => Promise<void> }

function defineProp(obj: any, key: string, value: any) {
  const prev = Object.getOwnPropertyDescriptor(obj, key);
  Object.defineProperty(obj, key, { value, configurable: true, writable: true });
  return () => {
    if (prev) Object.defineProperty(obj, key, prev);
    else delete obj[key];
  };
}

function mockShare(opts: ShareMock): () => void {
  const restoreSecure = defineProp(window as any, 'isSecureContext', opts.secure);
  const restoreShare = defineProp(navigator, 'share', opts.share ? (opts.shareImpl ?? (async () => {})) : undefined);
  const restoreCanShare = defineProp(navigator, 'canShare', opts.canShare ? (() => true) : undefined);
  return () => { restoreSecure(); restoreShare(); restoreCanShare(); };
}

describe('planDelivery', () => {
  it('plans copy for text', () => {
    const e = mkEntry({ type: 'text', content_type: 'text/plain', content: 'hi' });
    expect(planDelivery(e, null)).toEqual({ kind: 'copy', text: 'hi' });
  });

  it('plans open_link for link', () => {
    const e = mkEntry({ type: 'link', content_type: 'text/uri-list', content: 'https://x' });
    expect(planDelivery(e, null)).toEqual({ kind: 'open_link', href: 'https://x' });
  });

  it('plans render_html for html', () => {
    const e = mkEntry({ type: 'html', content_type: 'text/html', content: '<b>x</b>' });
    expect(planDelivery(e, null)).toEqual({ kind: 'render_html', html: '<b>x</b>' });
  });

  it('plans save_to_photos for an image when share API is available and context is secure', () => {
    const blob = new Blob([new Uint8Array([1])]);
    const e = mkEntry({ type: 'file', content_type: 'image/png', filename: 'p.png', size_bytes: 1 });
    const restore = mockShare({ secure: true, share: true, canShare: true });
    try {
      const action = planDelivery(e, { index: 0, content_type: 'image/png', size: 1, received: 1, blob, status: 'done' });
      expect(action.kind).toBe('save_to_photos');
    } finally {
      restore();
    }
  });

  it('falls back to save_blob for an image in a non-secure (HTTP) context even if share API is exposed', () => {
    const blob = new Blob([new Uint8Array([1])]);
    const e = mkEntry({ type: 'file', content_type: 'image/png', filename: 'p.png', size_bytes: 1 });
    const restore = mockShare({ secure: false, share: true, canShare: true });
    try {
      const action = planDelivery(e, { index: 0, content_type: 'image/png', size: 1, received: 1, blob, status: 'done' });
      expect(action.kind).toBe('save_blob');
    } finally {
      restore();
    }
  });

  it('plans save_blob for a file with blob', () => {
    const blob = new Blob([new Uint8Array([1])]);
    const e = mkEntry({ type: 'file', content_type: 'image/png', filename: 'p.png', size_bytes: 1 });
    const action = planDelivery(e, { index: 0, content_type: 'image/png', size: 1, received: 1, blob, status: 'done' });
    expect(['save_blob', 'save_to_photos']).toContain(action.kind);
  });

  it('plans none when file has no blob yet', () => {
    const e = mkEntry({ type: 'file', filename: 'p.png' });
    expect(planDelivery(e, { index: 0, content_type: '', size: 0, received: 0, status: 'downloading' })).toEqual({ kind: 'none' });
  });

  it('plans none for file entry with no blob and no content', () => {
    const e = mkEntry({ type: 'file', filename: 'p.png' });
    expect(planDelivery(e, null)).toEqual({ kind: 'none' });
  });
});

describe('applyDelivery', () => {
  it('falls back to download when navigator.share rejects with NotAllowedError', async () => {
    const blob = new Blob([new Uint8Array([1, 2, 3])], { type: 'image/png' });
    const action: DeliveryAction = { kind: 'save_to_photos', blob, filename: 'p.png' };
    const restore = mockShare({
      secure: true,
      share: true,
      canShare: true,
      shareImpl: () => Promise.reject(new DOMException('Permission denied', 'NotAllowedError')),
    });
    const created: string[] = [];
    const restoreCreate = defineProp(URL, 'createObjectURL', () => { const u = 'blob:mock'; created.push(u); return u; });
    const restoreRevoke = defineProp(URL, 'revokeObjectURL', () => {});
    const anchors: HTMLAnchorElement[] = [];
    const ceSpy = vi.spyOn(document, 'createElement').mockImplementation((tag: string) => {
      if (tag !== 'a') return document.createElement(tag);
      const a = { click: vi.fn(), remove: vi.fn(), href: '', download: '' } as unknown as HTMLAnchorElement;
      anchors.push(a);
      return a;
    });
    const appendSpy = vi.spyOn(document.body, 'appendChild').mockImplementation((n) => n as Node);
    try {
      await expect(applyDelivery(action)).resolves.toBeUndefined();
      expect(anchors.length).toBe(1);
      expect(anchors[0].download).toBe('p.png');
      expect(created.length).toBe(1);
    } finally {
      restore();
      restoreCreate();
      restoreRevoke();
      ceSpy.mockRestore();
      appendSpy.mockRestore();
    }
  });
});
