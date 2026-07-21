import { LoadingSpinner } from './ui/ProgressIndicator';

export function ConnectingScreen({ label = 'Connecting to PC…' }: { label?: string }) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background">
      <div className="pb-16">
        <LoadingSpinner message={label} />
      </div>
    </div>
  );
}