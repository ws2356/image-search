import { LoadingSpinner } from './ui/ProgressIndicator';

export function ConnectingScreen({ label = 'Connecting to PC…' }: { label?: string }) {
  return (
    <div className="min-h-screen bg-background">
      <LoadingSpinner message={label} />
    </div>
  );
}