import { log } from '../lib/log';
import type { ManifestFileEntry } from '../lib/protocol';
import type { FileProgress } from '../hooks/useTransfer';

export type DeliveryAction =
  | { kind: 'copy'; text: string }
  | { kind: 'open_link'; href: string }
  | { kind: 'render_html'; html: string }
  | { kind: 'save_blob'; blob: Blob; filename: string }
  | { kind: 'save_to_photos'; blob: Blob; filename: string }
  | { kind: 'none' };

export function planDelivery(entry: ManifestFileEntry, file: FileProgress | null): DeliveryAction {
  if (entry.type === 'text') {
    log.info('deliverer: plan copy', { index: entry.index });
    return { kind: 'copy', text: entry.content ?? '' };
  }
  if (entry.type === 'link') {
    log.info('deliverer: plan open_link', { index: entry.index, href: entry.content?.slice(0, 40) });
    return { kind: 'open_link', href: entry.content ?? '' };
  }
  if (entry.type === 'html') {
    log.info('deliverer: plan render_html', { index: entry.index });
    return { kind: 'render_html', html: entry.content ?? '' };
  }
  if (entry.type === 'file') {
    if (!file?.blob) {
      log.warn('deliverer: file has no blob yet', { index: entry.index });
      return { kind: 'none' };
    }
    if (entry.content_type.startsWith('image/') && typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
      log.info('deliverer: plan save_to_photos', { index: entry.index, filename: file.filename });
      return { kind: 'save_to_photos', blob: file.blob, filename: file.filename ?? 'image' };
    }
    log.info('deliverer: plan save_blob', { index: entry.index, filename: file.filename });
    return { kind: 'save_blob', blob: file.blob, filename: file.filename ?? 'file' };
  }
  log.warn('deliverer: unknown entry type', { index: entry.index, type: entry.type });
  return { kind: 'none' };
}

export async function applyDelivery(action: DeliveryAction): Promise<void> {
  log.info('deliverer: applyDelivery', action.kind);
  try {
    switch (action.kind) {
      case 'copy':
        if (navigator.clipboard) {
          await navigator.clipboard.writeText(action.text);
          log.info('deliverer: copy ok', { length: action.text.length });
        } else {
          log.warn('deliverer: clipboard API unavailable');
        }
        break;
      case 'open_link':
        log.info('deliverer: opening link', action.href.slice(0, 60));
        window.open(action.href, '_blank', 'noopener,noreferrer');
        break;
      case 'render_html': {
        log.info('deliverer: rendering html iframe', { htmlLength: action.html.length });
        const iframe = document.createElement('iframe');
        iframe.sandbox.add('allow-same-origin');
        iframe.srcdoc = action.html;
        iframe.style.cssText = 'width:100%;min-height:200px;border:1px solid #334155;border-radius:8px;';
        document.body.appendChild(iframe);
        break;
      }
      case 'save_blob': {
        log.info('deliverer: save_blob', { filename: action.filename, size: action.blob.size });
        const url = URL.createObjectURL(action.blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = action.filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
        break;
      }
      case 'save_to_photos': {
        const file = new File([action.blob], action.filename, { type: action.blob.type });
        if (navigator.share && navigator.canShare && navigator.canShare({ files: [file] })) {
          log.info('deliverer: navigator.share', { filename: action.filename });
          await navigator.share({ files: [file] });
        } else {
          log.info('deliverer: navigator.share unavailable, falling back to download', { filename: action.filename });
          const url = URL.createObjectURL(action.blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = action.filename;
          document.body.appendChild(a);
          a.click();
          a.remove();
          setTimeout(() => URL.revokeObjectURL(url), 1000);
        }
        break;
      }
      case 'none':
        log.debug('deliverer: no action');
        break;
    }
  } catch (err) {
    log.error('deliverer: applyDelivery failed', err);
    throw err;
  }
}
