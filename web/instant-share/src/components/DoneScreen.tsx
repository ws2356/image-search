import { useState, useCallback } from 'react';
import { log } from '../lib/log';
import type { FileProgress } from '../hooks/useTransfer';
import type { ManifestFileEntry } from '../lib/protocol';
import { planDelivery, applyDelivery, type DeliveryAction } from '../services/deliverer';

interface DoneItem {
  entry: ManifestFileEntry;
  file: FileProgress | null;
  action: DeliveryAction;
  delivered: boolean;
  error: string | null;
}

function actionLabel(action: DeliveryAction): string {
  switch (action.kind) {
    case 'copy': return 'Copy';
    case 'open_link': return 'Open Link';
    case 'render_html': return 'Show HTML';
    case 'save_blob': return 'Download';
    case 'save_to_photos': return 'Save to Photos';
    default: return 'No action';
  }
}

function itemLabel(entry: ManifestFileEntry): string {
  if (entry.type === 'text') return 'Text snippet';
  if (entry.type === 'link') return 'Link';
  if (entry.type === 'html') return 'HTML';
  return entry.filename ?? `file-${entry.index}`;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

export function DoneScreen({ files, manifest }: { files: FileProgress[]; manifest: ManifestFileEntry[] }) {
  const [items, setItems] = useState<DoneItem[]>(() =>
    manifest.map((entry) => {
      const file = files.find((f) => f.index === entry.index) ?? null;
      return { entry, file, action: planDelivery(entry, file), delivered: false, error: null };
    }),
  );

  const deliver = useCallback(async (index: number) => {
    const item = items.find((i) => i.entry.index === index);
    if (!item || item.delivered || item.action.kind === 'none') return;
    try {
      await applyDelivery(item.action);
      setItems((prev) => prev.map((i) => i.entry.index === index ? { ...i, delivered: true } : i));
    } catch (err) {
      log.error('DoneScreen: delivery failed', err);
      setItems((prev) => prev.map((i) => i.entry.index === index ? { ...i, error: String(err) } : i));
    }
  }, [items]);

  const deliverAll = useCallback(async () => {
    for (const item of items) {
      if (item.action.kind === 'none' || item.delivered) continue;
      if (item.action.kind === 'save_to_photos' || item.action.kind === 'open_link') continue;
      await deliver(item.entry.index);
    }
  }, [items, deliver]);

  return (
    <div className="min-h-screen bg-slate-950 px-4 py-8">
      <div className="mx-auto max-w-md">
        <div className="mb-6 text-center">
          <span className="text-4xl">{'\u2705'}</span>
          <h1 className="mt-2 text-lg font-semibold text-slate-100">All items received</h1>
          <p className="mt-1 text-xs text-slate-500">{items.length} item{items.length > 1 ? 's' : ''}</p>
        </div>

        <div className="flex flex-col gap-3">
          {items.map((item) => {
            const isImage = item.entry.type === 'file' && item.entry.content_type.startsWith('image/');
            return (
              <div key={item.entry.index} className="rounded-lg border border-slate-700 bg-slate-900 px-4 py-3">
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm text-slate-200">{itemLabel(item.entry)}</p>
                    {item.entry.type === 'file' && (
                      <p className="text-xs text-slate-500">{formatSize(item.file?.size ?? item.entry.size_bytes ?? 0)}</p>
                    )}
                  </div>
                  {item.action.kind !== 'none' && (
                    <button
                      onClick={() => deliver(item.entry.index)}
                      disabled={item.delivered}
      className={`shrink-0 rounded-md px-3 py-1.5 text-xs font-medium transition-colors ${
                        item.delivered
                          ? 'bg-green-900 text-green-300'
                          : 'bg-sky-600 text-white hover:bg-sky-500 active:bg-sky-700'
                      }`}
                    >
                      {item.delivered ? 'Done' : actionLabel(item.action)}
                    </button>
                  )}
                </div>
                {isImage && item.file?.blob && !item.delivered && (
                  <img
                    src={URL.createObjectURL(item.file.blob)}
                    alt={item.entry.filename ?? 'image'}
                    className="mt-3 w-full rounded-lg border border-slate-700"
                  />
                )}
                {item.error && (
                  <p className="mt-2 text-xs text-red-400">{item.error}</p>
                )}
              </div>
            );
          })}
        </div>

        <div className="mt-6 flex justify-center gap-3">
          <button
            onClick={deliverAll}
            className="rounded-md bg-slate-700 px-4 py-2 text-sm text-slate-200 hover:bg-slate-600"
          >
            Save All
          </button>
        </div>
      </div>
    </div>
  );
}
