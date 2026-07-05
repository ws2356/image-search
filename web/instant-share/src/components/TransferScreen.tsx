import type { FileProgress } from '../hooks/useTransfer';
import type { ManifestFileEntry } from '../lib/protocol';

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

function FileRow({ file, entry }: { file: FileProgress; entry: ManifestFileEntry }) {
  const pct = file.size > 0 ? Math.round((file.received / file.size) * 100) : 0;
  const statusIcon = file.status === 'done' ? '\u2705' : file.status === 'downloading' ? '\u23F3' : '\u23F3';
  const label = entry.type === 'text' ? 'Text snippet' : entry.type === 'link' ? 'Link' : entry.type === 'html' ? 'HTML' : (entry.filename ?? `file-${entry.index}`);
  return (
    <div className="rounded-lg border border-slate-700 bg-slate-900 px-4 py-3">
      <div className="flex items-center justify-between text-sm">
        <span className="truncate text-slate-200">{statusIcon} {label}</span>
        {entry.type === 'file' && (
          <span className="ml-2 shrink-0 text-slate-500">{formatSize(file.size)}</span>
        )}
      </div>
      {(file.status === 'downloading' || file.status === 'queued') && entry.type === 'file' && (
        <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-slate-700">
          <div className="h-full rounded-full bg-sky-500 transition-all duration-300" style={{ width: `${pct}%` }} />
        </div>
      )}
      {file.status === 'downloading' && entry.type === 'file' && (
        <p className="mt-1 text-xs text-slate-500">{formatSize(file.received)} / {formatSize(file.size)}</p>
      )}
    </div>
  );
}

export function TransferScreen({
  files,
  manifest,
}: {
  files: FileProgress[];
  manifest: ManifestFileEntry[];
}) {
  if (files.length === 0) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-4 bg-slate-950 text-slate-100">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-sky-500 border-t-transparent" />
        <p className="text-sm text-slate-400">Loading manifest…</p>
      </div>
    );
  }
  return (
    <div className="min-h-screen bg-slate-950 px-4 py-8">
      <h1 className="mb-2 text-lg font-semibold text-slate-100">Receiving from PC</h1>
      <p className="mb-6 text-xs text-slate-500">{files.length} item{files.length > 1 ? 's' : ''}</p>
      <div className="flex flex-col gap-2">
        {files.map((f) => {
          const entry = manifest[f.index];
          if (!entry) return null;
          return <FileRow key={f.index} file={f} entry={entry} />;
        })}
      </div>
    </div>
  );
}

