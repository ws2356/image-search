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
      <svg
        width={56}
        height={56}
        viewBox="0 0 24 24"
        fill="currentColor"
        className="text-warning"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" />
        <path d="M12 9v4" stroke="currentColor" strokeWidth={2} strokeLinecap="round" fill="none" />
        <path d="M12 17h.01" stroke="currentColor" strokeWidth={2} strokeLinecap="round" fill="none" />
      </svg>
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