# Instant Share Web App UI Overhaul

**Date:** 2026-07-07  
**Status:** Approved (design sections validated)  
**Scope:** `web/instant-share` — visual design system adoption + screen restructure

## 1. Goal

Overhaul the web/instant-share UI to adopt the same design system as the iOS native instant-share app (`mobile/ios-packages/InstantShareKit`, `ISFromPC` + `ISFromMobile`). Implement a shared token system, reusable components, and type-specific receive views that mirror the SwiftUI screens.

## 2. Context

The web app is a **receiver**: a browser opened via share URL that connects via WebRTC, authenticates with an opt code, receives a manifest, and downloads files of types text/link/html/file. The iOS native app has a formal `DesignSystem` (colors, typography, spacing, corner radii) and type-specific receive views (`QRTransferResultView` for text/HTML, `LinkReceiveView`, `MultiFileReceiveView`). The current web app has 4 ad-hoc screens with no design system.

### Key Findings

| Aspect | iOS Native | Current Web App | Decision |
|---|---|---|---|
| Theme | Light (white bg, black text, `#3B7DFA`/`#2563EB` blue) | Dark (slate-950 bg) | **Adopt iOS light theme** |
| Icons | SF Symbols | Emoji (✅ ❌ ⏳) | **lucide-react** |
| Receive views | Type-specific (text/link/multi-file) | One unified DoneScreen | **Type-specific, match iOS** |
| Progress + completion | Unified in MultiFileReceiveView | Split (TransferScreen + DoneScreen) | **Unify into ReceiveScreen** |
| Design tokens | DesignSystem.swift enums | None (ad-hoc Tailwind classes) | **Extending tailwind.config.ts** |
| Component library | SwiftUI (PrimaryButton, CardView, etc.) | None | **Small reusable component set** |

### Source Design System (iOS `DesignSystem.swift`)

**Colors** (ISFromPC variant — the canonical one for receive views):
```
background       = #FFFFFF
foreground       = #000000
primary          = #2563EB
cardBackground   = #F2F2F7
secondaryText    = #8E8E93
success          = #34C759
error            = #FF453A
warning          = #FF9F0A
border           = rgba(0,0,0,0.1)
selectedHighlight= rgba(37,99,235,0.1)
```

**Typography:** DM Sans (300–700) for body/UI, JetBrains Mono for code/text content.
- h1 = 24px bold, h2 = 20px bold, h3 = 18px semibold, h4 = 16px medium
- body = 15px regular, caption = 13px regular, caption2 = 11px regular
- monoBody = 14px regular (JetBrains Mono)

**Spacing:** xs=4, sm=8, md=12, lg=16, xl=24, xxl=32

**Corner Radius:** card=10px, button=14px, chip=8px, xl=16px

## 3. Approach

**Approach A (Approved): Design Tokens in Tailwind Config + Component Library.**

Extend `tailwind.config.ts` with iOS DesignSystem tokens as theme extensions. Add font `@import` for DM Sans + JetBrains Mono. Build a small reusable component set (`PrimaryButton`, `Card`, `ProgressIndicator`, `FileBadge`, `Toast`) mirroring the iOS SwiftUI components. Restructure screens to type-specific receive views.

Rejected alternatives:
- CSS custom properties + inline styles — verbose, no autocomplete, inconsistent tooling.
- Full shadcn/ui integration — overkill for a 4-screen receiver app; unnecessary Radix deps.

## 4. Design Token System

### `tailwind.config.ts` extensions

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

### `src/styles/index.css`

```css
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=JetBrains+Mono:wght@400;500;600&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;
```

## 5. Shared Components

All components in `src/components/ui/`, pure functional, TypeScript props, styled with Tailwind tokens. No state beyond local UI flags.

### `PrimaryButton.tsx`

Mirrors `ISFromPC/Views/Components/PrimaryButton.swift`.

```tsx
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
```

- Full-width, height 52px, `rounded-button` (14px), h4 font (16px medium)
- Variants:
  - `primary`: `bg-primary text-white`
  - `secondary`: `bg-transparent text-primary`
  - `destructive`: `bg-error/12 text-error` (error at 12% opacity)
- `isLoading`: replace icon with `Loader2` spinner (white for primary, primary for others)
- icon + title in `flex` row with `gap-sm` spacing

### `Card.tsx`

Mirrors `CardView.swift`.

```tsx
interface CardProps { children: ReactNode; className?: string; }
```

- `bg-card`, padding `lg` (16px), `rounded-card` (10px), `border border-border`

### `ProgressIndicator.tsx`

Mirrors `ProgressIndicator.swift`. Exports three components:

- `LoadingSpinner({ message })` — full-height centered: large spinner (`border-primary`), h3 foreground text
- `TransferProgress({ progress })` — `ProgressView`-style bar with primary tint + percentage caption
- `ScanningBadge()` — pulsing dot + "Scanning..." caption (available for future use, not active in current flows)

### `FileBadge.tsx`

Mirrors file extension badge + `statusIndicator(for:)` from `MultiFileReceiveView`.

```tsx
interface FileBadgeProps { filename: string; }
function StatusIndicator({ status }: { status: DownloadStatus }) {}
```

- `FileBadge`: 40x40 `rounded-chip` with 2-letter extension label (PNG/JPG/PDF/ZIP/TXT/FILE), badge color by file type:
  - image (png/jpg/jpeg): success at 20% bg, success text
  - pdf: primary at 20% bg, primary text
  - other: secondary at 20% bg, secondary text
- `StatusIndicator` sub-component:
  - `queued`: lucide `Clock` icon, secondary color
  - `downloading`: small `Loader2` spinner, primary color
  - `done`: green circle (success 10% bg) with lucide `Check` icon
  - `failed`: lucide `AlertCircle` icon (filled), error color

### `Toast.tsx`

Mirrors `toast()` helper in `QRTransferResultView`.

```tsx
interface ToastProps { message: string; visible: boolean; }
```

- Capsule shape, `bg-black/80 text-white`, body font
- Bottom slide-in transition (`translate-y` + opacity)
- Auto-managed by parent via `visible` prop (parent controls 2s timeout)

## 6. Screen Architecture

### `ConnectingScreen.tsx` (modified)

Kept, restyled. Full-screen centered `LoadingSpinner` with contextual label.

- Props: `{ label?: string }` (unchanged)
- Layout: `min-h-screen flex flex-col items-center justify-center bg-background`
- Uses `LoadingSpinner` component

### `ErrorScreen.tsx` (modified)

Kept, restyled. Full-screen error with warning icon + retry.

- Props: `{ error: { code: string; message: string }; retry?: () => void }` (add `retry`)
- Layout: `bg-background`, centered column with:
  - lucide `AlertTriangle` icon (56px, `text-warning`) — matches `ErrorView` SF Symbol
  - h2 "Transfer Failed" (`text-foreground`)
  - caption `{code}: {message}` (`text-secondary`)
  - Button row: `PrimaryButton` "Try Again" (primary, if `retry` provided) + link/button "Open Home Page" (secondary)

### `ReceiveScreen.tsx` (NEW — replaces TransferScreen + DoneScreen)

Unifies download progress and completion like iOS `MultiFileReceiveView`.

```tsx
interface ReceiveScreenProps {
  files: FileProgress[];
  manifest: ManifestFileEntry[];
  onDone?: () => void;
}
```

**Layout:**
```
VStack (min-h-screen, bg-background)
├── HeaderBar
│   ├── Left: "Received" (bold, body) + "{count} files from MacBook Pro" (caption2, secondary)
│   └── Right: "Done" button (h4, secondary) → calls onDone
├── Divider
├── [if isDownloading] ProgressBanner
│   └── spinner + "Receiving file {n} of {total}…" (caption semibold, primary) in primary/10 card
├── ScrollView → FileList
│   └── FileRow per entry (gap-sm, padding-lg)
│       ├── FileBadge (40x40 extension chip)
│       ├── FileInfo: filename (caption semibold) + "{size} · {status}" (caption2)
│       ├── [if done, inline content] inline preview (text/HTML/link)
│       └── StatusIndicator (right)
└── [if all done] BottomActionBar
    ├── Text/HTML: PrimaryButton "Copy to Clipboard" (green when copied 2s) + PrimaryButton "Share" (secondary)
    ├── Link: PrimaryButton "Copy Link" (secondary) + PrimaryButton "Open" (primary)
    └── Files: per-FileRow deliver button + global PrimaryButton "Save All" (primary)
```

**`FileRow` sub-component:**
- `HStack` with `gap-md`, file badge on left, file info in center (flex-1, truncate), status indicator on right
- `bg-background`, `rounded-button`, `border-border`, optional shadow when downloading (primary/10 glow)
- Opacity 0.6 for non-selectable (queued) rows
- Inline content (text/HTML/link) renders below the row when `done`:
  - **Text**: `<pre>` block using `font-mono`, `bg-card`, `rounded-xl`, scrollable
  - **HTML**: sandboxed `<iframe srcdoc={html}>` styled with card border
  - **Link**: simple link display with primary-colored text
- Action button appears to the right when `done` and `planDelivery` returns a non-`none` action

**Internal state:**
- `copiedIndex: number | null` — tracks which file's copy button is in "Copied!" state (2s timeout)
- Reuses `planDelivery` / `applyDelivery` from `deliverer.ts` per file
- `deliverAll()` helper iterates all files with non-none actions, calling `applyDelivery` sequentially

### `App.tsx` (modified)

Routing simplified:

```tsx
function AppContent() {
  // ... existing hook wiring (unchanged) ...
  if (transfer.status === 'error') {
    return <ErrorScreen error={...} retry={transfer.retry} />;
  }
  if (transfer.status === 'transferring' || transfer.status === 'done') {
    return <ReceiveScreen files={transfer.files} manifest={transfer.manifest ?? []} onDone={() => window.close()} />;
  }
  const label = labels[transfer.status] ?? 'Connecting to PC…';
  return <ConnectingScreen label={label} />;
}
```

The `done` and `transferring` states both render `ReceiveScreen` — `ReceiveScreen` shows the progress banner while downloads are in-flight and transitions to showing action buttons as each file reaches `done` status.

## 7. File Plan

### Added
- `src/components/ui/PrimaryButton.tsx`
- `src/components/ui/Card.tsx`
- `src/components/ui/ProgressIndicator.tsx`
- `src/components/ui/FileBadge.tsx`
- `src/components/ui/Toast.tsx`
- `src/components/ReceiveScreen.tsx`

### Modified
- `tailwind.config.ts` — design token extensions
- `src/styles/index.css` — DM Sans + JetBrains Mono font import
- `src/components/ConnectingScreen.tsx` — restyle with tokens + LoadingSpinner
- `src/components/ErrorScreen.tsx` — restyle with tokens, warning icon, retry support
- `src/App.tsx` — routing simplification (transferring/done → ReceiveScreen)
- `package.json` — add `lucide-react` dependency

### Deleted
- `src/components/TransferScreen.tsx` — merged into ReceiveScreen
- `src/components/DoneScreen.tsx` — merged into ReceiveScreen

## 8. Dependencies

- **Added:** `lucide-react` (icons) — matches figma-design project dependency
- **Unchanged:** `react`, `react-dom`, `tailwindcss`, `vite`, `vitest`, `typescript`
- **Not added:** No new state libraries, no component library (shadcn/Radix), no CSS framework beyond Tailwind v3

## 9. Testing

- `protocol.test.ts`, `urlParams.test.ts`, `deliverer.test.ts` — unchanged (no logic changes)
- No new tests required for the design token config or pure-presentational components
- Manual verification: run `pnpm dev`, test with a real share URL, verify all content types render correctly

## 10. Non-Goals

- Dark mode support (deferred — matching iOS which is light-only)
- QR scanning screen (web app receives via URL params, not camera)
- Device management / pairing (web app is an ephemeral receiver)
- Telemetry changes (existing `log` module stays)