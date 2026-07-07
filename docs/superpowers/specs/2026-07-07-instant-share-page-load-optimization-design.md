# Instant Share: Initial Page Load Speed Optimization

**Date**: 2026-07-07
**Scope**: `web/instant-share/`
**Goal**: Optimize first paint speed of the Instant Share web app.

## Problem

The Instant Share SPA has several critical rendering path issues that delay first meaningful paint:

1. **Google Fonts loaded via `@import url()` inside CSS** — creates a blocking chain: HTML → CSS parse → font fetch → text render. Text is invisible until fonts arrive (FOIT).
2. **No resource hints** — no preconnect, preload, or modulepreload in HTML.
3. **Single JS bundle (~174KB)** — `ReceiveScreen` + `lucide-react` icons load eagerly even when the user only sees the connecting spinner.
4. **`cleanExpired()` IndexedDB sweep runs on every mount** — adds latency to first render.

## Current State

- **Bundle**: 174KB JS, 9.7KB CSS (Vite production build)
- **Dependencies**: react, react-dom, lucide-react (tree-shaken per import)
- **Fonts**: DM Sans + JetBrains Mono loaded via `@import url('https://fonts.googleapis.com/css2?family=...')` in `src/styles/index.css`
- **Entry**: `index.html` → `src/main.tsx` → `src/App.tsx`

## Design

### 1. Fix font loading (`index.html`, `src/styles/index.css`)

**Remove** the `@import url(...)` line from `src/styles/index.css`.

**Add to `<head>` in `index.html`**:

```html
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
```

**Why**: Preconnect eliminates DNS+TLS latency. `preload` starts the fetch immediately. `media="print" onload="this.media='all'"` loads the stylesheet non-blocking. `display=swap` (already in the URL) shows fallback text immediately.

### 2. Resource hints (`index.html`)

Vite 5 enables `build.modulePreload` by default, which injects `<link rel="modulepreload">` for JS chunks into the built `dist/index.html`. No additional config needed — verify after build.

Add explicit `<link rel="preload">` for the CSS file. Since the filename is hashed, this must be injected at build time. Vite does this automatically for the CSS `<link>` tag, and `modulePreload` handles JS. No manual work required beyond verifying the built output.

### 3. Code-split connecting vs receiving flows (`src/App.tsx`)

**Current**: `OnlineFlow` eagerly imports `ReceiveScreen`, which pulls in 4 lucide-react icons (Copy, Download, ExternalLink, Check). When the user lands on the page, they see a connecting spinner but the browser already downloaded receiving UI code.

**Change**:

```tsx
const ReceiveScreen = React.lazy(() => import('./components/ReceiveScreen'));
```

Wrap the receiving path in `<Suspense>`:

```tsx
<Suspense fallback={<ConnectingScreen label="Loading…" />}>
  <ReceiveScreen files={files} manifest={manifest} />
</Suspense>
```

**Keep eagerly imported**: `ConnectingScreen` (no lucide-react dependency), `ErrorScreen` (see below).

**Resulting chunks**:
- **Critical**: React + `ConnectingScreen` + hooks + protocol + cache (~80-90KB)
- **Lazy**: `ReceiveScreen` + lucide-react icons + deliverer (~80-90KB) — loaded when transfer completes

### 4. Remove lucide-react from ErrorScreen (`src/components/ErrorScreen.tsx`)

`ErrorScreen` uses `AlertTriangle` from lucide-react. To keep it in the critical chunk without pulling in lucide-react:

Replace:
```tsx
import { AlertTriangle } from 'lucide-react';
// ...
<AlertTriangle size={56} className="text-warning" fill="currentColor" />
```

With an inline SVG matching the lucide AlertTriangle icon:
```tsx
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
```

### 5. Defer cache cleanup (`src/App.tsx`)

Move `cleanExpired()` from synchronous `useEffect` to `requestIdleCallback`:

```tsx
useEffect(() => {
  if ('requestIdleCallback' in window) {
    requestIdleCallback(() => cleanExpired().catch(() => {}));
  } else {
    setTimeout(() => cleanExpired().catch(() => {}), 0);
  }
}, []);
```

### 6. Vite config tweak (`vite.config.ts`)

Add `build.modulePreload.polyfill: false` since target browsers are modern (WebRTC-capable):

```ts
build: {
  modulePreload: false, // removes ~1KB polyfill
},
```

## Files Changed

| File | Change |
|------|--------|
| `index.html` | Add preconnect, preload hints, async font stylesheet, noscript fallback |
| `src/styles/index.css` | Remove `@import url(...)` line |
| `src/App.tsx` | `React.lazy` for `ReceiveScreen`, `Suspense` boundary, defer `cleanExpired` |
| `src/components/ErrorScreen.tsx` | Replace lucide `AlertTriangle` with inline SVG |
| `vite.config.ts` | Set `modulePreload: false` |

## What We're NOT Changing

- No service worker or offline strategy
- No Tailwind CSS config changes
- No changes to relay, WebSocket, or WebRTC logic
- No new npm dependencies
- No changes to test files

## Verification

1. Run `pnpm run build` and inspect `dist/` output:
   - Verify `<link rel="modulepreload">` tags present in `dist/index.html`
   - Verify no `@import url(...)` in the CSS file
   - Verify preconnect/preload hints in `dist/index.html`
   - Verify two JS chunks (critical + lazy) in `dist/assets/`
2. Run `pnpm run test` — all existing tests should pass
3. Run `pnpm run preview` and verify:
   - Connecting spinner appears immediately
   - Network tab shows fonts loading in parallel (not blocking)
   - `ReceiveScreen` chunk loads only after transfer completes
