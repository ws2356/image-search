import { useState, useCallback } from 'react';
import { Copy, Download, ExternalLink, Check } from 'lucide-react';
import type { FileProgress } from '../hooks/useTransfer';
import type { ManifestFileEntry } from '../lib/protocol';
import { planDelivery, applyDelivery, type DeliveryAction } from '../services/deliverer';
import { log } from '../lib/log';
import { PrimaryButton } from './ui/PrimaryButton';
import { Card } from './ui/Card';
import { FileBadge, StatusIndicator } from './ui/FileBadge';
import { Toast } from './ui/Toast';

interface ReceiveScreenProps {
  files: FileProgress[];
  manifest: ManifestFileEntry[];
  onDone?: () => void;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function statusText(status: FileProgress['status']): string {
  switch (status) {
    case 'queued': return 'Queued';
    case 'downloading': return 'Receiving…';
    case 'done': return 'Received';
  }
}

function statusColor(status: FileProgress['status']): string {
  switch (status) {
    case 'queued': return 'text-secondary';
    case 'downloading': return 'text-primary';
    case 'done': return 'text-success';
  }
}

function actionLabel(action: DeliveryAction): string {
  switch (action.kind) {
    case 'copy': return 'Copy';
    case 'open_link': return 'Open Link';
    case 'render_html': return 'Show HTML';
    case 'save_blob': return 'Download';
    case 'save_to_photos': return 'Save to Photos';
    default: return '';
  }
}

function actionIcon(action: DeliveryAction) {
  switch (action.kind) {
    case 'copy': return Copy;
    case 'open_link': return ExternalLink;
    case 'render_html': return ExternalLink;
    case 'save_blob': return Download;
    case 'save_to_photos': return Download;
    default: return Download;
  }
}

export function ReceiveScreen({ files, manifest, onDone }: ReceiveScreenProps) {
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);
  const [delivered, setDelivered] = useState<Set<number>>(new Set());
  const [errors, setErrors] = useState<Record<number, string>>({});

  const totalCount = files.length;
  const downloadedCount = files.filter((f) => f.status === 'done').length;
  const isDownloading = files.some((f) => f.status === 'downloading' || f.status === 'queued');

  const deliver = useCallback(async (index: number) => {
    const entry = manifest[index];
    const file = files.find((f) => f.index === index) ?? null;
    if (!entry) return;
    const action = planDelivery(entry, file);
    if (action.kind === 'none') return;
    try {
      await applyDelivery(action);
      if (action.kind === 'copy') {
        setCopiedIndex(index);
        setTimeout(() => setCopiedIndex(null), 2000);
      }
      setDelivered((prev) => new Set(prev).add(index));
    } catch (err) {
      log.error('ReceiveScreen: delivery failed', err);
      setErrors((prev) => ({ ...prev, [index]: String(err) }));
    }
  }, [files, manifest]);

  const deliverAll = useCallback(async () => {
    for (const entry of manifest) {
      if (delivered.has(entry.index)) continue;
      const file = files.find((f) => f.index === entry.index) ?? null;
      const action = planDelivery(entry, file);
      if (action.kind === 'none' || action.kind === 'save_to_photos' || action.kind === 'open_link') continue;
      await deliver(entry.index);
    }
  }, [manifest, files, delivered, deliver]);

  const hasFileItems = files.some((f) => f.status === 'done' && manifest[f.index]?.type === 'file');

  return (
    <div className="min-h-screen bg-background">
      <header className="flex items-center justify-between px-lg py-md">
        <div className="flex flex-col gap-xs">
          <span className="text-sm font-bold text-foreground">Received</span>
          <span className="text-[11px] text-secondary">
            {totalCount} {totalCount === 1 ? 'file' : 'files'} from MacBook Pro
          </span>
        </div>
        <button
          onClick={onDone}
          className="text-base font-medium text-secondary hover:text-foreground"
        >
          Done
        </button>
      </header>

      <div className="border-t border-border" />

      {isDownloading && (
        <div className="flex items-center gap-sm px-lg py-sm">
          <div className="flex flex-1 items-center gap-sm rounded-button bg-primary/10 px-md py-md">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
            <span className="text-xs font-semibold text-primary">
              Receiving file {downloadedCount + 1} of {totalCount}…
            </span>
          </div>
        </div>
      )}

      <div className="overflow-y-auto p-lg">
        <div className="flex flex-col gap-sm">
          {files.map((file) => {
            const entry = manifest[file.index];
            if (!entry) return null;
            const isInline = entry.type === 'text' || entry.type === 'link' || entry.type === 'html';
            const isDone = file.status === 'done';
            const isSelectable = isInline || isDone;
            const action = isDone ? planDelivery(entry, file) : { kind: 'none' } as DeliveryAction;
            const copied = copiedIndex === file.index;
            const wasDelivered = delivered.has(file.index);

            return (
              <div
                key={file.index}
                className={`rounded-button border bg-background p-md transition-opacity ${
                  file.status === 'downloading'
                    ? 'border-primary/20 shadow-[0_0_3px_rgba(37,99,235,0.1)]'
                    : 'border-border'
                } ${!isSelectable ? 'opacity-60' : ''}`}
              >
                <div className="flex items-center gap-md">
                  {entry.type === 'file' ? (
                    <FileBadge filename={entry.filename ?? `file-${entry.index}`} />
                  ) : (
                    <FileBadge filename={entry.type === 'link' ? 'link.url' : entry.type === 'html' ? 'page.html' : 'text.txt'} />
                  )}

                  <div className="flex flex-1 flex-col gap-xs overflow-hidden">
                    <span className="truncate text-xs font-semibold text-foreground">
                      {entry.type === 'text' ? 'Text snippet'
                        : entry.type === 'link' ? 'Link'
                        : entry.type === 'html' ? 'HTML'
                        : (entry.filename ?? `file-${entry.index}`)}
                    </span>
                    <div className="flex items-center gap-xs">
                      {entry.type === 'file' && (
                        <span className="text-[11px] text-secondary">
                          {formatSize(file.size)}
                        </span>
                      )}
                      {entry.type === 'file' && <span className="text-[11px] text-secondary">·</span>}
                      <span className={`text-[11px] ${statusColor(file.status)}`}>
                        {isInline ? 'Received' : statusText(file.status)}
                      </span>
                    </div>
                  </div>

                  <StatusIndicator status={file.status} />
                </div>

                {isDone && isInline && entry.type === 'text' && entry.content && (
                  <pre className="mt-sm max-h-48 overflow-auto rounded-xl bg-card p-lg font-mono text-xs text-foreground whitespace-pre-wrap">
                    {entry.content}
                  </pre>
                )}

                {isDone && isInline && entry.type === 'link' && entry.content && (
                  <Card className="mt-sm flex flex-col items-center gap-sm">
                    <ExternalLink size={32} className="text-primary" />
                    <span className="text-sm font-semibold text-foreground">Web Link</span>
                    <span className="break-all text-center text-sm text-primary">{entry.content}</span>
                  </Card>
                )}

                {isDone && isInline && entry.type === 'html' && entry.content && (
                  <iframe
                    sandbox="allow-same-origin"
                    srcDoc={entry.content}
                    className="mt-sm h-48 w-full rounded-card border border-border"
                    title="HTML content"
                  />
                )}

                {isDone && entry.type === 'file' && file.blob && entry.content_type.startsWith('image/') && !wasDelivered && (
                  <img
                    src={URL.createObjectURL(file.blob)}
                    alt={entry.filename ?? 'image'}
                    className="mt-sm w-full rounded-card border border-border"
                  />
                )}

                {errors[file.index] && (
                  <p className="mt-sm text-xs text-error">{errors[file.index]}</p>
                )}

                {isDone && action.kind !== 'none' && (
                  <div className="mt-sm flex gap-md">
                    <div className="flex-1">
                      <PrimaryButton
                        title={copied ? 'Copied!' : actionLabel(action)}
                        icon={copied ? Check : actionIcon(action)}
                        variant={copied ? 'primary' : 'secondary'}
                        onClick={() => deliver(file.index)}
                        disabled={wasDelivered && !copied}
                      />
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {!isDownloading && hasFileItems && (
        <div className="px-lg pb-xxl">
          <PrimaryButton title="Save All" icon={Download} variant="primary" onClick={() => deliverAll()} />
        </div>
      )}

      <Toast message="Copied!" visible={copiedIndex !== null} />
    </div>
  );
}