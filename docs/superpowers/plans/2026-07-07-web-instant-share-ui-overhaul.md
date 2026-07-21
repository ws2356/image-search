# Instant Share Web App UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul web/instant-share UI to adopt the iOS native instant-share DesignSystem (light theme, DM Sans/JetBrains Mono fonts, `#2563EB` primary) with reusable components and type-specific receive views.

**Architecture:** Extend `tailwind.config.ts` with iOS design tokens. Build a small reusable component set (PrimaryButton, Card, ProgressIndicator, FileBadge, Toast) mirroring iOS SwiftUI components. Merge TransferScreen + DoneScreen into a unified ReceiveScreen with type-specific inline previews (text/link/html/file) matching iOS `MultiFileReceiveView` + `QRTransferResultView` + `LinkReceiveView`. No changes to hooks, services, or protocol logic.

**Tech Stack:** React 18, TypeScript, Tailwind CSS v3, Vite, vitest, lucide-react (new dep), DM Sans + JetBrains Mono (Google Fonts)

**Spec:** `docs/superpowers/specs/2026-07-07-web-instant-share-ui-overhaul-design.md`

## Global Constraints

- **Theme:** Light mode only — white bg (`#FFFFFF`), black text (`#000000`), primary blue `#2563EB`, card gray `#F2F2F7`, secondary gray `#8E8E93`, success `#34C759`, error `#FF453A`, warning `#FF9F0A`, border `rgba(0,0,0,0.1)`. Matches `ISFromPC/Views/Components/DesignSystem.swift`.
- **Fonts:** DM Sans (sans) + JetBrains Mono (mono) via Google Fonts `@import`.
- **Icons:** `lucide-react` — no emoji characters in UI.
- **No logic changes:** `useTransfer`, `useSignalChannel`, `useWebRTC`, `deliverer.ts`, `protocol.ts`, `urlParams.ts` are untouched.
- **Existing tests must pass:** `protocol.test.ts`, `urlParams.test.ts`, `deliverer.test.ts` untouched and must remain green.
- **TypeScript strict:** `noUnusedLocals`, `noUnusedParameters`, `strict` all on.
- **Working dir for all commands:** `web/instant-share`
- **Package manager:** `pnpm`
- **Test command:** `pnpm test` (runs vitest in dev mode)
- **Build command:** `pnpm build` (runs `tsc -b && vite build`)
- **Dev command:** `pnpm dev`

---

### Task 1: Install lucide-react and Configure Design Tokens

**Files:**
- Modify: `web/instant-share/package.json`
- Modify: `web/instant-share/tailwind.config.ts`
- Modify: `web/instant-share/src/styles/index.css`
- Modify: `web/instant-share/index.html`

**Interfaces:**
- Produces: Tailwind theme tokens `bg-background`, `text-foreground`, `bg-primary`, `text-primary`, `bg-card`, `text-secondary`, `text-success`, `bg-success`, `text-error`, `text-warning`, `bg-selected`, `border-border`, `font-sans`, `font-mono`, spacing `p-xs`/`p-sm`/`p-md`/`p-lg`/`p-xl`/`p-xxl`, radius `rounded-card`/`rounded-button`/`rounded-chip`/`rounded-xl`.

- [ ] **Step 1: Install lucide-react**

Run from `web/instant-share`:
```bash
pnpm add lucide-react
```
Expected: `lucide-react` added to `dependencies` in `package.json`, lockfile updated.

- [ ] **Step 2: Replace tailwind.config.ts with token extensions**

Replace the entire contents of `web/instant-share/tailwind.config.ts` with:

```ts
import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        background: '#FFFFFF',
        foreground: '#000000',
        primary: '#2563EB',
        card: '#F2F2F7',
        secondary: '#8E8E93',
        success: '#34C759',
        error: '#FF453A',
        warning: '#FF9F0A',
        selected: 'rgba(37, 99, 235, 0.1)',
      },
      borderColor: {
        DEFAULT: 'rgba(0, 0, 0, 0.1)',
      },
      fontFamily: {
        sans: ['"DM Sans"', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      spacing: {
        xs: '4px',
        sm: '8px',
        md: '12px',
        lg: '16px',
        xl: '24px',
        xxl: '32px',
      },
      borderRadius: {
        card: '10px',
        button: '14px',
        chip: '8px',
        xl: '16px',
      },
    },
  },
  plugins: [],
} satisfies Config;
```

- [ ] **Step 3: Add font imports to index.css**

Replace the entire contents of `web/instant-share/src/styles/index.css` with:

```css
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=JetBrains+Mono:wght@400;500;600&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;
```

- [ ] **Step 4: Update index.html body classes for light theme**

In `web/instant-share/index.html`, change the `<body>` tag from:
```html
  <body class="bg-slate-950 text-slate-100">
```
to:
```html
  <body class="bg-background text-foreground">
```

- [ ] **Step 5: Verify build and tests pass**

Run:
```bash
pnpm test && pnpm build
```
Expected: All existing tests pass (3 test files). Build succeeds with no TypeScript errors.

- [ ] **Step 6: Commit**

```bash
git add web/instant-share/package.json web/instant-share/pnpm-lock.yaml web/instant-share/tailwind.config.ts web/instant-share/src/styles/index.css web/instant-share/index.html
git commit -m "feat(web-instant-share): add design tokens and lucide-react dependency"
```

---

### Task 2: Build PrimaryButton Component

**Files:**
- Create: `web/instant-share/src/components/ui/PrimaryButton.tsx`
- Test: `web/instant-share/src/components/ui/PrimaryButton.test.tsx`

**Interfaces:**
- Produces: `PrimaryButton` component with props `{ title: string; icon?: LucideIcon; variant?: 'primary' | 'secondary' | 'destructive'; isLoading?: boolean; disabled?: boolean; onClick?: () => void }`.

- [ ] **Step 1: Write the failing test**

Create `web/instant-share/src/components/ui/PrimaryButton.test.tsx`:

```tsx
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
pnpm test src/components/ui/PrimaryButton.test.tsx
```
Expected: FAIL — `PrimaryButton` module not found.

- [ ] **Step 3: Write the PrimaryButton component**

Create `web/instant-share/src/components/ui/PrimaryButton.tsx`:

```tsx
import { Loader2, type LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';

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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
pnpm test src/components/ui/PrimaryButton.test.tsx
```
Expected: PASS — 3 tests pass.

- [ ] **Step 5: Run full test suite to verify no regressions**

Run:
```bash
pnpm test
```
Expected: All test files pass.

- [ ] **Step 6: Commit**

```bash
git add web/instant-share/src/components/ui/PrimaryButton.tsx web/instant-share/src/components/ui/PrimaryButton.test.tsx
git commit -m "feat(web-instant-share): add PrimaryButton component"
```

---

### Task 3: Build Card Component

**Files:**
- Create: `web/instant-share/src/components/ui/Card.tsx`
- Test: `web/instant-share/src/components/ui/Card.test.tsx`

**Interfaces:**
- Produces: `Card` component with props `{ children: ReactNode; className?: string }`.

- [ ] **Step 1: Write the failing test**

Create `web/instant-share/src/components/ui/Card.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { Card } from './Card';

describe('Card', () => {
  it('renders children content', () => {
    render(<Card><span data-testid="inner">Hello</span></Card>);
    expect(screen.getByTestId('inner')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
pnpm test src/components/ui/Card.test.tsx
```
Expected: FAIL — `Card` module not found.

- [ ] **Step 3: Write the Card component**

Create `web/instant-share/src/components/ui/Card.tsx`:

```tsx
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
pnpm test src/components/ui/Card.test.tsx
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/src/components/ui/Card.tsx web/instant-share/src/components/ui/Card.test.tsx
git commit -m "feat(web-instant-share): add Card component"
```

---

### Task 4: Build ProgressIndicator Components

**Files:**
- Create: `web/instant-share/src/components/ui/ProgressIndicator.tsx`
- Test: `web/instant-share/src/components/ui/ProgressIndicator.test.tsx`

**Interfaces:**
- Produces: `LoadingSpinner({ message?: string })`, `TransferProgress({ progress: number })`.

- [ ] **Step 1: Write the failing test**

Create `web/instant-share/src/components/ui/ProgressIndicator.test.tsx`:

```tsx
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
pnpm test src/components/ui/ProgressIndicator.test.tsx
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the ProgressIndicator component**

Create `web/instant-share/src/components/ui/ProgressIndicator.tsx`:

```tsx
import { Loader2 } from 'lucide-react';

export function LoadingSpinner({ message = 'Connecting...' }: { message?: string }) {
  return (
    <div className="flex h-full w-full flex-col items-center justify-center gap-lg">
      <Loader2 size={40} className="animate-spin text-primary" />
      <p className="text-lg font-semibold text-foreground">{message}</p>
    </div>
  );
}

export function TransferProgress({ progress }: { progress: number }) {
  const pct = Math.round(progress * 100);
  return (
    <div className="flex flex-col gap-sm">
      <div className="h-2 w-full overflow-hidden rounded-full bg-card">
        <div
          className="h-full rounded-full bg-primary transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
      <p className="text-xs text-secondary">{pct}%</p>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
pnpm test src/components/ui/ProgressIndicator.test.tsx
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/src/components/ui/ProgressIndicator.tsx web/instant-share/src/components/ui/ProgressIndicator.test.tsx
git commit -m "feat(web-instant-share): add ProgressIndicator components"
```

---

### Task 5: Build FileBadge + StatusIndicator

**Files:**
- Create: `web/instant-share/src/components/ui/FileBadge.tsx`
- Test: `web/instant-share/src/components/ui/FileBadge.test.tsx`

**Interfaces:**
- Produces: `FileBadge({ filename: string })`, `StatusIndicator({ status: 'queued' | 'downloading' | 'done' | 'failed' })`.

- [ ] **Step 1: Write the failing test**

Create `web/instant-share/src/components/ui/FileBadge.test.tsx`:

```tsx
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
pnpm test src/components/ui/FileBadge.test.tsx
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the FileBadge + StatusIndicator component**

Create `web/instant-share/src/components/ui/FileBadge.tsx`:

```tsx
import { Clock, Loader2, Check, AlertCircle } from 'lucide-react';

export type DownloadStatus = 'queued' | 'downloading' | 'done' | 'failed';

function fileExtension(filename: string): string {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'PNG';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'JPG';
  if (lower.endsWith('.pdf')) return 'PDF';
  if (lower.endsWith('.zip')) return 'ZIP';
  if (lower.endsWith('.txt')) return 'TXT';
  return 'FILE';
}

function badgeColors(filename: string): { bg: string; text: string } {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return { bg: 'bg-success/20', text: 'text-success' };
  }
  if (lower.endsWith('.pdf')) {
    return { bg: 'bg-primary/20', text: 'text-primary' };
  }
  return { bg: 'bg-secondary/20', text: 'text-secondary' };
}

export function FileBadge({ filename }: { filename: string }) {
  const ext = fileExtension(filename);
  const { bg, text } = badgeColors(filename);
  return (
    <div
      className={`flex h-10 w-10 items-center justify-center rounded-chip ${bg}`}
    >
      <span className={`text-[9px] font-black tracking-wide ${text}`}>{ext}</span>
    </div>
  );
}

export function StatusIndicator({ status }: { status: DownloadStatus }) {
  switch (status) {
    case 'queued':
      return <Clock size={16} className="text-secondary" />;
    case 'downloading':
      return <Loader2 size={16} className="animate-spin text-primary" />;
    case 'done':
      return (
        <div className="flex h-6 w-6 items-center justify-center rounded-full bg-success/10">
          <Check size={12} className="font-bold text-success" />
        </div>
      );
    case 'failed':
      return <AlertCircle size={16} className="text-error" fill="currentColor" />;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
pnpm test src/components/ui/FileBadge.test.tsx
```
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/src/components/ui/FileBadge.tsx web/instant-share/src/components/ui/FileBadge.test.tsx
git commit -m "feat(web-instant-share): add FileBadge and StatusIndicator components"
```

---

### Task 6: Build Toast Component

**Files:**
- Create: `web/instant-share/src/components/ui/Toast.tsx`
- Test: `web/instant-share/src/components/ui/Toast.test.tsx`

**Interfaces:**
- Produces: `Toast({ message: string; visible: boolean })`.

- [ ] **Step 1: Write the failing test**

Create `web/instant-share/src/components/ui/Toast.test.tsx`:

```tsx
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
pnpm test src/components/ui/Toast.test.tsx
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the Toast component**

Create `web/instant-share/src/components/ui/Toast.tsx`:

```tsx
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
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
pnpm test src/components/ui/Toast.test.tsx
```
Expected: PASS — 2 tests.

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/src/components/ui/Toast.tsx web/instant-share/src/components/ui/Toast.test.tsx
git commit -m "feat(web-instant-share): add Toast component"
```

---

### Task 7: Build ReceiveScreen (unified Transfer + Done)

**Files:**
- Create: `web/instant-share/src/components/ReceiveScreen.tsx`
- Test: `web/instant-share/src/components/ReceiveScreen.test.tsx`
- Delete after: `web/instant-share/src/components/TransferScreen.tsx`
- Delete after: `web/instant-share/src/components/DoneScreen.tsx`

**Interfaces:**
- Consumes: `FileProgress` from `../hooks/useTransfer` (`{ index, filename?, content_type, size, received, blob?, status: 'queued'|'downloading'|'done' }`), `ManifestFileEntry` from `../lib/protocol` (`{ index, type: 'text'|'link'|'html'|'file', content_type, size_bytes?, filename?, content? }`), `planDelivery` + `applyDelivery` from `../services/deliverer`, `PrimaryButton`, `Card`, `FileBadge`, `StatusIndicator`, `Toast`, lucide icons.
- Produces: `ReceiveScreen({ files: FileProgress[]; manifest: ManifestFileEntry[]; onDone?: () => void })`.

- [ ] **Step 1: Write the failing test**

Create `web/instant-share/src/components/ReceiveScreen.test.tsx`:

```tsx
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
    expect(screen.getByText('Received')).toBeInTheDocument();
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
pnpm test src/components/ReceiveScreen.test.tsx
```
Expected: FAIL — module not found.

- [ ] **Step 3: Write the ReceiveScreen component**

Create `web/instant-share/src/components/ReceiveScreen.tsx`:

```tsx
import { useState, useCallback } from 'react';
import { Copy, Share2, Download, ExternalLink, Check } from 'lucide-react';
import type { FileProgress } from '../hooks/useTransfer';
import type { ManifestFileEntry } from '../lib/protocol';
import { planDelivery, applyDelivery, type DeliveryAction } from '../services/deliverer';
import { log } from '../lib/log';
import { PrimaryButton } from './ui/PrimaryButton';
import { Card } from './ui/Card';
import { FileBadge, StatusIndicator } from './ui/FileBadge';
import { Toast } from './ui/Toast';

interface ReceiveScreenProps {
  files: FileProgress[];
  manifest: ManifestFileEntry[];
  onDone?: () => void;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function statusText(status: FileProgress['status']): string {
  switch (status) {
    case 'queued': return 'Queued';
    case 'downloading': return 'Receiving…';
    case 'done': return 'Received';
  }
}

function statusColor(status: FileProgress['status']): string {
  switch (status) {
    case 'queued': return 'text-secondary';
    case 'downloading': return 'text-primary';
    case 'done': return 'text-success';
  }
}

function actionLabel(action: DeliveryAction): string {
  switch (action.kind) {
    case 'copy': return 'Copy';
    case 'open_link': return 'Open Link';
    case 'render_html': return 'Show HTML';
    case 'save_blob': return 'Download';
    case 'save_to_photos': return 'Save to Photos';
    default: return '';
  }
}

function actionIcon(action: DeliveryAction) {
  switch (action.kind) {
    case 'copy': return Copy;
    case 'open_link': return ExternalLink;
    case 'render_html': return ExternalLink;
    case 'save_blob': return Download;
    case 'save_to_photos': return Download;
    default: return Download;
  }
}

export function ReceiveScreen({ files, manifest, onDone }: ReceiveScreenProps) {
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);
  const [delivered, setDelivered] = useState<Set<number>>(new Set());
  const [errors, setErrors] = useState<Record<number, string>>({});

  const totalCount = files.length;
  const downloadedCount = files.filter((f) => f.status === 'done').length;
  const isDownloading = files.some((f) => f.status === 'downloading' || f.status === 'queued');

  const deliver = useCallback(async (index: number) => {
    const entry = manifest[index];
    const file = files.find((f) => f.index === index) ?? null;
    if (!entry) return;
    const action = planDelivery(entry, file);
    if (action.kind === 'none') return;
    try {
      await applyDelivery(action);
      if (action.kind === 'copy') {
        setCopiedIndex(index);
        setTimeout(() => setCopiedIndex(null), 2000);
      }
      setDelivered((prev) => new Set(prev).add(index));
    } catch (err) {
      log.error('ReceiveScreen: delivery failed', err);
      setErrors((prev) => ({ ...prev, [index]: String(err) }));
    }
  }, [files, manifest]);

  const deliverAll = useCallback(async () => {
    for (const entry of manifest) {
      if (delivered.has(entry.index)) continue;
      const file = files.find((f) => f.index === entry.index) ?? null;
      const action = planDelivery(entry, file);
      if (action.kind === 'none' || action.kind === 'save_to_photos' || action.kind === 'open_link') continue;
      await deliver(entry.index);
    }
  }, [manifest, files, delivered, deliver]);

  return (
    <div className="min-h-screen bg-background">
      <header className="flex items-center justify-between px-lg py-md">
        <div className="flex flex-col gap-xs">
          <span className="text-sm font-bold text-foreground">Received</span>
          <span className="text-[11px] text-secondary">
            {totalCount} {totalCount === 1 ? 'file' : 'files'} from MacBook Pro
          </span>
        </div>
        <button
          onClick={onDone}
          className="text-base font-medium text-secondary hover:text-foreground"
        >
          Done
        </button>
      </header>

      <div className="border-t border-border" />

      {isDownloading && (
        <div className="flex items-center gap-sm px-lg py-sm">
          <div className="flex flex-1 items-center gap-sm rounded-button bg-primary/10 px-md py-md">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-primary border-t-transparent" />
            <span className="text-xs font-semibold text-primary">
              Receiving file {downloadedCount + 1} of {totalCount}…
            </span>
          </div>
        </div>
      )}

      <div className="overflow-y-auto p-lg">
        <div className="flex flex-col gap-sm">
          {files.map((file) => {
            const entry = manifest[file.index];
            if (!entry) return null;
            const isInline = entry.type === 'text' || entry.type === 'link' || entry.type === 'html';
            const isDone = file.status === 'done';
            const isSelectable = isInline || isDone;
            const action = isDone ? planDelivery(entry, file) : { kind: 'none' } as DeliveryAction;
            const copied = copiedIndex === file.index;
            const wasDelivered = delivered.has(file.index);

            return (
              <div
                key={file.index}
                className={`rounded-button border bg-background p-md transition-opacity ${
                  file.status === 'downloading'
                    ? 'border-primary/20 shadow-[0_0_3px_rgba(37,99,235,0.1)]'
                    : 'border-border'
                } ${!isSelectable ? 'opacity-60' : ''}`}
              >
                <div className="flex items-center gap-md">
                  {entry.type === 'file' ? (
                    <FileBadge filename={entry.filename ?? `file-${entry.index}`} />
                  ) : (
                    <FileBadge filename={entry.type === 'link' ? 'link.url' : entry.type === 'html' ? 'page.html' : 'text.txt'} />
                  )}

                  <div className="flex flex-1 flex-col gap-xs overflow-hidden">
                    <span className="truncate text-xs font-semibold text-foreground">
                      {entry.type === 'text' ? 'Text snippet'
                        : entry.type === 'link' ? 'Link'
                        : entry.type === 'html' ? 'HTML'
                        : (entry.filename ?? `file-${entry.index}`)}
                    </span>
                    <div className="flex items-center gap-xs">
                      {entry.type === 'file' && (
                        <span className="text-[11px] text-secondary">
                          {formatSize(file.size)}
                        </span>
                      )}
                      {entry.type === 'file' && <span className="text-[11px] text-secondary">·</span>}
                      <span className={`text-[11px] ${statusColor(file.status)}`}>
                        {isInline ? 'Received' : statusText(file.status)}
                      </span>
                    </div>
                  </div>

                  <StatusIndicator status={file.status} />
                </div>

                {isDone && isInline && entry.type === 'text' && entry.content && (
                  <pre className="mt-sm max-h-48 overflow-auto rounded-xl bg-card p-lg font-mono text-xs text-foreground whitespace-pre-wrap">
                    {entry.content}
                  </pre>
                )}

                {isDone && isInline && entry.type === 'link' && entry.content && (
                  <Card className="mt-sm flex flex-col items-center gap-sm">
                    <ExternalLink size={32} className="text-primary" />
                    <span className="text-sm font-semibold text-foreground">Web Link</span>
                    <span className="break-all text-center text-sm text-primary">{entry.content}</span>
                  </Card>
                )}

                {isDone && isInline && entry.type === 'html' && entry.content && (
                  <iframe
                    sandbox="allow-same-origin"
                    srcDoc={entry.content}
                    className="mt-sm h-48 w-full rounded-card border border-border"
                    title="HTML content"
                  />
                )}

                {isDone && entry.type === 'file' && file.blob && entry.content_type.startsWith('image/') && !wasDelivered && (
                  <img
                    src={URL.createObjectURL(file.blob)}
                    alt={entry.filename ?? 'image'}
                    className="mt-sm w-full rounded-card border border-border"
                  />
                )}

                {errors[file.index] && (
                  <p className="mt-sm text-xs text-error">{errors[file.index]}</p>
                )}

                {isDone && action.kind !== 'none' && (
                  <div className="mt-sm flex gap-md">
                    <div className="flex-1">
                      <PrimaryButton
                        title={copied ? 'Copied!' : actionLabel(action)}
                        icon={copied ? Check : actionIcon(action)}
                        variant={copied ? 'primary' : 'secondary'}
                        onClick={() => deliver(file.index)}
                        disabled={wasDelivered && !copied}
                      />
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {!isDownloading && files.some((f) => f.status === 'done' && manifest[f.index]?.type === 'file') && (
        <div className="px-lg pb-xxl">
          <PrimaryButton title="Save All" icon={Download} variant="primary" onClick={() => deliverAll()} />
        </div>
      )}

      <Toast message="Copied!" visible={copiedIndex !== null} />
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
pnpm test src/components/ReceiveScreen.test.tsx
```
Expected: PASS — 4 tests.

- [ ] **Step 5: Run full test suite**

Run:
```bash
pnpm test
```
Expected: All tests pass.

- [ ] **Step 6: Delete old TransferScreen and DoneScreen**

```bash
rm web/instant-share/src/components/TransferScreen.tsx web/instant-share/src/components/DoneScreen.tsx
```

- [ ] **Step 7: Verify build still compiles** (will fail until App.tsx is updated in Task 8)

This is expected — the build will fail because App.tsx still imports the deleted files. We'll fix this in Task 8.

- [ ] **Step 8: Commit**

```bash
git add web/instant-share/src/components/ReceiveScreen.tsx web/instant-share/src/components/ReceiveScreen.test.tsx web/instant-share/src/components/TransferScreen.tsx web/instant-share/src/components/DoneScreen.tsx
git commit -m "feat(web-instant-share): add ReceiveScreen, remove TransferScreen and DoneScreen"
```

---

### Task 8: Update App.tsx, ConnectingScreen, ErrorScreen

**Files:**
- Modify: `web/instant-share/src/App.tsx`
- Modify: `web/instant-share/src/components/ConnectingScreen.tsx`
- Modify: `web/instant-share/src/components/ErrorScreen.tsx`

**Interfaces:**
- Consumes: `ReceiveScreen` from Task 7, `LoadingSpinner` from Task 4, `PrimaryButton` from Task 2, lucide icons.
- App.tsx routing: `transferring` and `done` states both render `ReceiveScreen`.

- [ ] **Step 1: Rewrite ConnectingScreen with design tokens**

Replace entire contents of `web/instant-share/src/components/ConnectingScreen.tsx` with:

```tsx
import { LoadingSpinner } from './ui/ProgressIndicator';

export function ConnectingScreen({ label = 'Connecting to PC…' }: { label?: string }) {
  return (
    <div className="min-h-screen bg-background">
      <LoadingSpinner message={label} />
    </div>
  );
}
```

- [ ] **Step 2: Rewrite ErrorScreen with design tokens and retry support**

Replace entire contents of `web/instant-share/src/components/ErrorScreen.tsx` with:

```tsx
import { AlertTriangle } from 'lucide-react';
import { PrimaryButton } from './ui/PrimaryButton';

const HOME = 'https://dl.boldman.net';

export function ErrorScreen({
  error,
  retry,
}: {
  error: { code: string; message: string };
  retry?: () => void;
}) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-xl bg-background px-xl text-center">
      <AlertTriangle size={56} className="text-warning" fill="currentColor" />
      <h2 className="text-xl font-bold text-foreground">Transfer Failed</h2>
      <p className="text-xs text-secondary">{error.code}: {error.message}</p>
      <div className="flex gap-lg">
        {retry && (
          <div className="flex-1">
            <PrimaryButton title="Try Again" variant="primary" onClick={retry} />
          </div>
        )}
        <div className="flex-1">
          <a href={HOME} className="block">
            <PrimaryButton title="Open Home Page" variant="secondary" />
          </a>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Rewrite App.tsx routing**

Replace entire contents of `web/instant-share/src/App.tsx` with:

```tsx
import { parseShareUrlParams } from './lib/urlParams';
import { useSignalChannel } from './hooks/useSignalChannel';
import { useWebRTC } from './hooks/useWebRTC';
import { useTransfer } from './hooks/useTransfer';
import { ConnectingScreen } from './components/ConnectingScreen';
import { ReceiveScreen } from './components/ReceiveScreen';
import { ErrorScreen } from './components/ErrorScreen';
import { log } from './lib/log';

const RELAY_URL = import.meta.env.VITE_RELAY_URL;

if (!RELAY_URL) {
  throw new Error('RELAY_URL is not defined in environment variables');
}

function AppContent() {
  const params = parseShareUrlParams(window.location.search);
  if (!params) {
    log.warn('App: invalid or missing URL params');
    return <ErrorScreen error={{ code: 'bad_url', message: 'Missing or invalid share parameters' }} />;
  }

  const signal = useSignalChannel(RELAY_URL, params.sessionId, 'browser');
  const webrtc = useWebRTC(signal);
  const transfer = useTransfer(params, webrtc);

  if (transfer.status === 'error') {
    log.warn('App: rendering ErrorScreen', transfer.error);
    return <ErrorScreen error={transfer.error ?? { code: 'unknown', message: '' }} retry={transfer.retry} />;
  }

  if (transfer.status === 'transferring' || transfer.status === 'done') {
    const files = transfer.files.length > 0 ? transfer.files : [];
    const manifest = transfer.manifest ?? [];
    return <ReceiveScreen files={files} manifest={manifest} onDone={() => { window.close(); }} />;
  }

  const labels: Record<string, string> = {
    connecting: 'Connecting to PC…',
    authenticating: 'Authenticating with PC…',
    booting: 'Loading…',
  };
  const label = labels[transfer.status] ?? 'Connecting to PC…';
  return <ConnectingScreen label={label} />;
}

export default function App() {
  return <AppContent />;
}
```

- [ ] **Step 4: Run full test suite**

Run:
```bash
pnpm test
```
Expected: All tests pass (existing 3 test files + new component tests).

- [ ] **Step 5: Verify build compiles**

Run:
```bash
pnpm build
```
Expected: TypeScript compiles with no errors, Vite build succeeds producing `dist/`.

- [ ] **Step 6: Commit**

```bash
git add web/instant-share/src/App.tsx web/instant-share/src/components/ConnectingScreen.tsx web/instant-share/src/components/ErrorScreen.tsx
git commit -m "feat(web-instant-share): update App routing, restyle Connecting and Error screens"
```

---

### Task 9: Manual Smoke Test

**Files:** None (verification only)

- [ ] **Step 1: Start dev server**

Run:
```bash
pnpm dev
```
Expected: Vite dev server starts on port 5173.

- [ ] **Step 2: Verify the ConnectingScreen renders**

Open browser to `http://localhost:5173/?sid=invalid&opt=invalid` (invalid params that trigger error path). Verify:
- White background (not dark slate)
- Blue spinner spinning
- DM Sans font applied (check via DevTools → Computed → font-family)
- Connecting message shows

- [ ] **Step 3: Verify ErrorScreen renders**

With the invalid URL above, you should see the ErrorScreen:
- Warning triangle icon (orange/weapons)
- "Transfer Failed" heading in bold black
- Error code/message in secondary gray
- "Try Again" button (blue primary) and "Open Home Page" button (blue secondary)

- [ ] **Step 4: Final commit if any fixes were needed**

If smoke test revealed issues, fix and commit:
```bash
git add -A
git commit -m "fix(web-instant-share): address smoke test findings"
```