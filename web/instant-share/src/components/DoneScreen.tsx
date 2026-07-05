export function DoneScreen() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-3 bg-slate-950 text-slate-100">
      <span className="text-4xl">{'\u2705'}</span>
      <h1 className="text-lg font-semibold">All items received</h1>
      <p className="text-xs text-slate-500">You can close this page.</p>
    </div>
  );
}
