import { render, screen } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import { PrimaryButton } from './PrimaryButton';

describe('PrimaryButton', () => {
  it('renders the title text', () => {
    render(<PrimaryButton title="Copy" variant="primary" onClick={() => {}} />);
    expect(screen.getByText('Copy')).toBeInTheDocument();
  });

  it('is disabled when isLoading is true', () => {
    render(<PrimaryButton title="Send" variant="primary" isLoading onClick={() => {}} />);
    expect(screen.getByRole('button')).toBeDisabled();
  });

  it('calls onClick when clicked', () => {
    const onClick = vi.fn();
    render(<PrimaryButton title="Open" variant="primary" onClick={onClick} />);
    screen.getByRole('button').click();
    expect(onClick).toHaveBeenCalledTimes(1);
  });
});