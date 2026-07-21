import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { Card } from './Card';

describe('Card', () => {
  it('renders children content', () => {
    render(<Card><span data-testid="inner">Hello</span></Card>);
    expect(screen.getByTestId('inner')).toBeInTheDocument();
  });
});