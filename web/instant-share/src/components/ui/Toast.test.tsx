import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { Toast } from './Toast';

describe('Toast', () => {
  it('renders message when visible', () => {
    render(<Toast message="Copied!" visible={true} />);
    expect(screen.getByText('Copied!')).toBeInTheDocument();
  });

  it('does not render when not visible', () => {
    const { container } = render(<Toast message="Copied!" visible={false} />);
    expect(container.firstChild).toBeNull();
  });
});