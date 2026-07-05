const HOME = 'https://dl.boldman.net';

export function ErrorScreen({ error: { code, message } }: { error: { code: string; message: string } }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-3 bg-slate-950 px-6 text-center text-slate-100">
      <span className="text-4xl">{'\u274C'}</span>
      <h1 className="text-lg font-semibold">Transfer failed</h1>
      <p className="text-xs text-slate-500">{code}: {message}</p>
      <a href={HOME} className="mt-4 rounded-lg bg-sky-600 px-5 py-2 text-sm font-medium text-white hover:bg-sky-500">Open Home Page</a>
    </div>
  );
}
