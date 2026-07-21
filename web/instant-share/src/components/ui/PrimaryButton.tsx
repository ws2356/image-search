import { Loader2, type LucideIcon } from 'lucide-react';

type Variant = 'primary' | 'secondary' | 'destructive';

interface PrimaryButtonProps {
  title: string;
  icon?: LucideIcon;
  variant?: Variant;
  isLoading?: boolean;
  disabled?: boolean;
  onClick?: () => void;
}

const variantStyles: Record<Variant, string> = {
  primary: 'bg-primary text-white',
  secondary: 'bg-transparent text-primary',
  destructive: 'bg-error/10 text-error',
};

export function PrimaryButton({
  title,
  icon: Icon,
  variant = 'primary',
  isLoading = false,
  disabled = false,
  onClick,
}: PrimaryButtonProps) {
  return (
    <button
      onClick={onClick}
      disabled={isLoading || disabled}
      className={`flex w-full items-center justify-center gap-sm rounded-button px-lg py-md text-base font-medium transition-colors disabled:opacity-50 ${variantStyles[variant]}`}
      style={{ height: 52 }}
    >
      {isLoading ? (
        <Loader2 size={18} className="animate-spin" />
      ) : Icon ? (
        <Icon size={18} />
      ) : null}
      <span>{title}</span>
    </button>
  );
}