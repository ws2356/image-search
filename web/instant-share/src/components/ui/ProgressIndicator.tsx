import { Loader2 } from 'lucide-react';

export function LoadingSpinner({ message = 'Connecting...' }: { message?: string }) {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-lg">
      <Loader2 size={40} className="animate-spin text-primary" />
      <p className="text-lg font-semibold text-foreground">{message}</p>
    </div>
  );
}

export function TransferProgress({ progress }: { progress: number }) {
  const pct = Math.round(progress * 100);
  return (
    <div className="flex flex-col gap-sm">
      <div className="h-2 w-full overflow-hidden rounded-full bg-card">
        <div
          className="h-full rounded-full bg-primary transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
      <p className="text-xs text-secondary">{pct}%</p>
    </div>
  );
}