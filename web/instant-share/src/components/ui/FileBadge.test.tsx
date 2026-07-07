import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { FileBadge, StatusIndicator } from './FileBadge';

describe('FileBadge', () => {
  it('shows PNG extension for image file', () => {
    render(<FileBadge filename="photo.png" />);
    expect(screen.getByText('PNG')).toBeInTheDocument();
  });

  it('shows PDF extension', () => {
    render(<FileBadge filename="doc.pdf" />);
    expect(screen.getByText('PDF')).toBeInTheDocument();
  });

  it('shows FILE for unknown extension', () => {
    render(<FileBadge filename="data.xyz" />);
    expect(screen.getByText('FILE')).toBeInTheDocument();
  });
});

describe('StatusIndicator', () => {
  it('renders without crashing for each status', () => {
    const { rerender } = render(<StatusIndicator status="queued" />);
    rerender(<StatusIndicator status="downloading" />);
    rerender(<StatusIndicator status="done" />);
    rerender(<StatusIndicator status="failed" />);
  });
});