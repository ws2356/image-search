import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { ReceiveScreen } from './ReceiveScreen';
import type { FileProgress } from '../hooks/useTransfer';
import type { ManifestFileEntry } from '../lib/protocol';

const manifest: ManifestFileEntry[] = [
  { index: 0, type: 'file', content_type: 'image/png', size_bytes: 10240, filename: 'photo.png' },
  { index: 1, type: 'text', content_type: 'text/plain', content: 'Hello world' },
];

const files: FileProgress[] = [
  { index: 0, filename: 'photo.png', content_type: 'image/png', size: 10240, received: 10240, status: 'done' },
  { index: 1, content_type: 'text/plain', size: 11, received: 11, status: 'done' },
];

describe('ReceiveScreen', () => {
  it('renders header with file count', () => {
    render(<ReceiveScreen files={files} manifest={manifest} />);
    expect(screen.getByText(/2 files/)).toBeInTheDocument();
  });

  it('renders Done button', () => {
    render(<ReceiveScreen files={files} manifest={manifest} />);
    expect(screen.getByText('Done')).toBeInTheDocument();
  });

  it('renders filenames', () => {
    render(<ReceiveScreen files={files} manifest={manifest} />);
    expect(screen.getByText('photo.png')).toBeInTheDocument();
  });

  it('shows progress banner when downloading', () => {
    const downloadingFiles: FileProgress[] = [
      { index: 0, filename: 'doc.pdf', content_type: 'application/pdf', size: 5000, received: 2000, status: 'downloading' },
    ];
    const downloadingManifest: ManifestFileEntry[] = [
      { index: 0, type: 'file', content_type: 'application/pdf', size_bytes: 5000, filename: 'doc.pdf' },
    ];
    render(<ReceiveScreen files={downloadingFiles} manifest={downloadingManifest} />);
    expect(screen.getByText(/Receiving file 1 of 1/)).toBeInTheDocument();
  });
});