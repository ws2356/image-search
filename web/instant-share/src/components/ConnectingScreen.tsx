export function ConnectingScreen({ label = 'Connecting to PC…' }: { label?: string }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 bg-slate-950 text-slate-100">
      <div className="h-8 w-8 animate-spin rounded-full border-2 border-sky-500 border-t-transparent" />
      <p className="text-sm text-slate-400">{label}</p>
    </div>
  );
}
