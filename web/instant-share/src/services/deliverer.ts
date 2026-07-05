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
    return { kind: 'copy', text: entry.content ?? '' };
  }
  if (entry.type === 'link') {
    return { kind: 'open_link', href: entry.content ?? '' };
  }
  if (entry.type === 'html') {
    return { kind: 'render_html', html: entry.content ?? '' };
  }
  if (entry.type === 'file') {
    if (!file?.blob) return { kind: 'none' };
    if (entry.content_type.startsWith('image/') && typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
      return { kind: 'save_to_photos', blob: file.blob, filename: file.filename ?? 'image' };
    }
    return { kind: 'save_blob', blob: file.blob, filename: file.filename ?? 'file' };
  }
  return { kind: 'none' };
}

export async function applyDelivery(action: DeliveryAction): Promise<void> {
  switch (action.kind) {
    case 'copy':
      if (navigator.clipboard) await navigator.clipboard.writeText(action.text);
      break;
    case 'open_link':
      window.open(action.href, '_blank', 'noopener,noreferrer');
      break;
    case 'render_html': {
      const iframe = document.createElement('iframe');
      iframe.sandbox.add('allow-same-origin');
      iframe.srcdoc = action.html;
      iframe.style.cssText = 'width:100%;min-height:200px;border:1px solid #334155;border-radius:8px;';
      document.body.appendChild(iframe);
      break;
    }
    case 'save_blob': {
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
        await navigator.share({ files: [file] });
      } else {
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
      break;
  }
}
