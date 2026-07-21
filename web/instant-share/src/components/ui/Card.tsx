import type { ReactNode } from 'react';

interface CardProps {
  children: ReactNode;
  className?: string;
}

export function Card({ children, className = '' }: CardProps) {
  return (
    <div className={`rounded-card border border-border bg-card p-lg ${className}`}>
      {children}
    </div>
  );
}