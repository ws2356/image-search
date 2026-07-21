import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { LoadingSpinner, TransferProgress } from './ProgressIndicator';

describe('LoadingSpinner', () => {
  it('shows the message text', () => {
    render(<LoadingSpinner message="Connecting..." />);
    expect(screen.getByText('Connecting...')).toBeInTheDocument();
  });

  it('shows default message when none provided', () => {
    render(<LoadingSpinner />);
    expect(screen.getByText('Connecting...')).toBeInTheDocument();
  });
});

describe('TransferProgress', () => {
  it('shows percentage for 0.65 progress', () => {
    render(<TransferProgress progress={0.65} />);
    expect(screen.getByText('65%')).toBeInTheDocument();
  });
});