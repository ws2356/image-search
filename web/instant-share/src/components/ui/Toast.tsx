interface ToastProps {
  message: string;
  visible: boolean;
}

export function Toast({ message, visible }: ToastProps) {
  if (!visible) return null;
  return (
    <div className="fixed inset-x-0 bottom-xxl flex justify-center">
      <div className="rounded-full bg-black/80 px-xl py-sm text-sm text-white shadow-lg">
        {message}
      </div>
    </div>
  );
}