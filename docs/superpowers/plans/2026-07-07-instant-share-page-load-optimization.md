# Instant Share Page Load Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize first paint speed of the Instant Share web app by fixing the critical rendering path.

**Architecture:** Move Google Fonts from render-blocking CSS `@import` to async `<link>` in HTML, code-split the app so the connecting flow loads without receiving UI code, and defer non-critical IndexedDB cleanup.

**Tech Stack:** React 18, Vite 5, Tailwind CSS 3, TypeScript

## Global Constraints

- No new npm dependencies
- No changes to relay, WebSocket, or WebRTC logic
- No changes to test files
- All file paths relative to `web/instant-share/`

---

### Task 1: Fix font loading and add resource hints

**Files:**
- Modify: `index.html`
- Modify: `src/styles/index.css`

**Interfaces:**
- Produces: HTML `<head>` with preconnect + async font stylesheet; CSS without `@import`

- [ ] **Step 1: Remove the `@import` from CSS**

In `src/styles/index.css`, remove line 1:
```css
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=JetBrains+Mono:wght@400;500;600&display=swap');
```

The file should now contain only:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

- [ ] **Step 2: Add font loading to `index.html` `<head>`**

Replace the entire `<head>` section in `index.html` with:

```html
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Instant Share</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link
    rel="preload"
    as="style"
    href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=JetBrains+Mono:wght@400;500;600&display=swap"
  />
  <link
    rel="stylesheet"
    href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=JetBrains+Mono:wght@400;500;600&display=swap"
    media="print"
    onload="this.media='all'"
  />
  <noscript>
    <link
      rel="stylesheet"
      href="https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;0,9..40,700;1,9..40,400&family=JetBrains+Mono:wght@400;500;600&display=swap"
    />
  </noscript>
</head>
```

- [ ] **Step 3: Verify the build output**

Run: `pnpm run build`

Check `dist/index.html` contains:
- `<link rel="preconnect"` tags
- `<link rel="preload" as="style"` tags
- `<link rel="stylesheet" ... media="print"` tags
- The `@import` is gone from the CSS file in `dist/assets/`

- [ ] **Step 4: Commit**

```bash
git add index.html src/styles/index.css
git commit -m "perf: fix render-blocking font loading, add preconnect hints

[LLM: mimo-v2.5-pro]"
```

---

### Task 2: Code-split ReceiveScreen and inline ErrorScreen icon

**Files:**
- Modify: `src/App.tsx`
- Modify: `src/components/ErrorScreen.tsx`

**Interfaces:**
- Consumes: `ConnectingScreen` (eagerly imported, unchanged)
- Produces: `ReceiveScreen` as a lazy-loaded component behind `<Suspense>`

- [ ] **Step 1: Replace lucide icon in ErrorScreen**

In `src/components/ErrorScreen.tsx`, replace the entire file with:

```tsx
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
      <svg
        width={56}
        height={56}
        viewBox="0 0 24 24"
        fill="currentColor"
        className="text-warning"
        xmlns="http://www.w3.org/2000/svg"
      >
        <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" />
        <path d="M12 9v4" stroke="currentColor" strokeWidth={2} strokeLinecap="round" fill="none" />
        <path d="M12 17h.01" stroke="currentColor" strokeWidth={2} strokeLinecap="round" fill="none" />
      </svg>
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

- [ ] **Step 2: Add React.lazy for ReceiveScreen in App.tsx**

In `src/App.tsx`, add the lazy import after the existing imports (after line 11):

```tsx
import React, { Suspense } from 'react';
```

Add the lazy import after the other imports:

```tsx
const ReceiveScreen = React.lazy(() => import('./components/ReceiveScreen').then(m => ({ default: m.ReceiveScreen })));
```

- [ ] **Step 3: Wrap ReceiveScreen usage in Suspense**

In `src/App.tsx`, in the `OnlineFlow` function, replace the `ReceiveScreen` usage (around line 30-33):

```tsx
if (transfer.state.type === 'transferring' || transfer.state.type === 'done') {
  const files = transfer.files.length > 0 ? transfer.files : [];
  const manifest = transfer.manifest ?? [];
  return (
    <Suspense fallback={<ConnectingScreen label="Loading…" />}>
      <ReceiveScreen files={files} manifest={manifest} />
    </Suspense>
  );
}
```

Also in `AppContent`, replace the cached `ReceiveScreen` usage (around line 98-100):

```tsx
if (cached) {
  return (
    <Suspense fallback={<ConnectingScreen label="Loading…" />}>
      <ReceiveScreen files={cached.files} manifest={cached.manifest} />
    </Suspense>
  );
}
```

- [ ] **Step 4: Update React import to include Suspense**

The import at line 1 of `src/App.tsx` currently is:
```tsx
import { useState, useEffect } from 'react';
```

Change it to:
```tsx
import React, { useState, useEffect, Suspense } from 'react';
```

- [ ] **Step 5: Verify tests pass**

Run: `pnpm run test`
Expected: All tests pass.

- [ ] **Step 6: Verify build produces two chunks**

Run: `pnpm run build`
Expected: `dist/assets/` contains at least 2 JS files (the main chunk and a lazy chunk for ReceiveScreen + lucide-react).

- [ ] **Step 7: Commit**

```bash
git add src/App.tsx src/components/ErrorScreen.tsx
git commit -m "perf: code-split ReceiveScreen, inline ErrorScreen icon

[LLM: mimo-v2.5-pro]"
```

---

### Task 3: Defer cache cleanup and disable modulePreload polyfill

**Files:**
- Modify: `src/App.tsx`
- Modify: `vite.config.ts`

**Interfaces:**
- No new interfaces. Changes are internal optimizations.

- [ ] **Step 1: Defer cleanExpired in App.tsx**

In `src/App.tsx`, in the `AppContent` function, replace the `useEffect` that calls `cleanExpired()` (lines 54-92). Find this block:

```tsx
useEffect(() => {
  cleanExpired().catch(() => {});
  // ... rest of the effect
}, [params.sessionId]);
```

Replace just the `cleanExpired()` call at the top of the effect body. Change:
```tsx
cleanExpired().catch(() => {});
```
To:
```tsx
if ('requestIdleCallback' in window) {
  (window as any).requestIdleCallback(() => cleanExpired().catch(() => {}));
} else {
  setTimeout(() => cleanExpired().catch(() => {}), 0);
}
```

- [ ] **Step 2: Disable modulePreload polyfill in vite.config.ts**

In `vite.config.ts`, add `build` config inside the return object (after the `base` line):

```ts
build: {
  modulePreload: false,
},
```

The full config should look like:

```ts
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  console.log('Vite config: loaded env', { mode, env });
  return {
    plugins: [react()],
    server: { port: 5173 },
    test: {
      globals: true,
      environment: 'jsdom',
      setupFiles: './src/test/setup.ts',
      exclude: ['**/node_modules/**', '**/dist/**', '**/relay/**'],
    },
    base: env.VITE_BASE || '/',
    build: {
      modulePreload: false,
    },
  }
});
```

- [ ] **Step 3: Verify tests pass**

Run: `pnpm run test`
Expected: All tests pass.

- [ ] **Step 4: Verify build output**

Run: `pnpm run build`
Expected: No `modulepreload` polyfill in the built JS. `dist/index.html` should still have `<link rel="modulepreload">` tags for the chunks (Vite injects these).

- [ ] **Step 5: Commit**

```bash
git add src/App.tsx vite.config.ts
git commit -m "perf: defer cache cleanup, disable modulePreload polyfill

[LLM: mimo-v2.5-pro]"
```
