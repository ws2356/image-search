import { describe, it, expect } from 'vitest';
import { planDelivery } from './deliverer';
import type { ManifestFileEntry } from '../lib/protocol';

const mkEntry = (over: Partial<ManifestFileEntry>): ManifestFileEntry => ({
  index: 0,
  type: 'file',
  content_type: 'application/octet-stream',
  ...over,
});

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
