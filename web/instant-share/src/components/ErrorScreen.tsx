import { AlertTriangle } from 'lucide-react';
import { PrimaryButton } from './ui/PrimaryButton';

const HOME = 'https://dl.boldman.net';

export function ErrorScreen({
  error,
  retry,
}: {
  error: { code: string; message: string };
  retry?: () => void;
}) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-xl bg-background px-xl text-center">
      <AlertTriangle size={56} className="text-warning" fill="currentColor" />
      <h2 className="text-xl font-bold text-foreground">Transfer Failed</h2>
      <p className="text-xs text-secondary">{error.code}: {error.message}</p>
      <div className="flex gap-lg">
        {retry && (
          <div className="flex-1">
            <PrimaryButton title="Try Again" variant="primary" onClick={retry} />
          </div>
        )}
        <div className="flex-1">
          <a href={HOME} className="block">
            <PrimaryButton title="Open Home Page" variant="secondary" />
          </a>
        </div>
      </div>
    </div>
  );
}