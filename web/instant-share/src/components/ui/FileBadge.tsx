import { Clock, Loader2, Check, AlertCircle } from 'lucide-react';

export type DownloadStatus = 'queued' | 'downloading' | 'done' | 'failed';

function fileExtension(filename: string): string {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'PNG';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'JPG';
  if (lower.endsWith('.pdf')) return 'PDF';
  if (lower.endsWith('.zip')) return 'ZIP';
  if (lower.endsWith('.txt')) return 'TXT';
  return 'FILE';
}

function badgeColors(filename: string): { bg: string; text: string } {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return { bg: 'bg-success/20', text: 'text-success' };
  }
  if (lower.endsWith('.pdf')) {
    return { bg: 'bg-primary/20', text: 'text-primary' };
  }
  return { bg: 'bg-secondary/20', text: 'text-secondary' };
}

export function FileBadge({ filename }: { filename: string }) {
  const ext = fileExtension(filename);
  const { bg, text } = badgeColors(filename);
  return (
    <div
      className={`flex h-10 w-10 items-center justify-center rounded-chip ${bg}`}
    >
      <span className={`text-[9px] font-black tracking-wide ${text}`}>{ext}</span>
    </div>
  );
}

export function StatusIndicator({ status }: { status: DownloadStatus }) {
  switch (status) {
    case 'queued':
      return <Clock size={16} className="text-secondary" />;
    case 'downloading':
      return <Loader2 size={16} className="animate-spin text-primary" />;
    case 'done':
      return (
        <div className="flex h-6 w-6 items-center justify-center rounded-full bg-success/10">
          <Check size={12} className="font-bold text-success" />
        </div>
      );
    case 'failed':
      return <AlertCircle size={16} className="text-error" fill="currentColor" />;
  }
}