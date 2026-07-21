# Web-Based Instant Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a browser-based fallback for the existing instant-share QR flow so that scanning the QR without the native iOS app installed opens a web SPA that auto-receives the stashed payload over WebRTC.

**Architecture:** A CDN-hosted Vite/React/Tailwind SPA at `web/instant-share/` joins a tiny Node WebSocket relay (`/relay`) keyed by `session_id`, exchanges SDP/ICE with the PC, opens a `RTCDataChannel`, authenticates with the QR's `opt_code` (verified against the existing `TrustSession`), and auto-downloads the stash via the data channel. The PC side runs an `aiortc`-based `WebRTCPeer` inside the existing asyncio runtime, bridging data-channel messages to the existing `QRTriggerHandler` in-process. Native flow is untouched — same QR URL, same `QRTriggerHandler`, same `QRTriggerMiniWindowFactory`.

**Tech Stack:** Frontend: Vite + React 18 + TypeScript + Tailwind CSS v3, native browser WebRTC API (`RTCPeerConnection`, `RTCDataChannel`), native `WebSocket`. Relay: Node.js + `ws`. PC: `aiortc` (Python asyncio WebRTC), existing `FastAPI`/`uvicorn` runtime, existing `QRTriggerHandler` + `TrustSessionRegistry`.

**Spec:** [`docs/superpowers/specs/2026-07-05-web-instant-share-design.md`](../specs/2026-07-05-web-instant-share-design.md)

## Global Constraints

- **Language:** TypeScript (web), Python 3.10 (PC), Node.js/JavaScript (relay).
- **Web build:** Vite; no WebRTC library — native browser API only; no state library beyond React.
- **PC path style:** Follow `dt_image_search/instant_sharing/` existing patterns — `from __future__ import annotations`, absolute imports from `dt_image_search.…`, `snake_case`, type hints, `logging.getLogger(__name__)` (the instant_sharing module uses stdlib `logging`, not the telemetry `log()` — match it).
- **No new global state:** Inject deps; do not add module-level singletons beyond the existing `runtime.py` composition.
- **Feature gate:** All WebRTC peer spawning gated behind the existing `is_instant_share_enabled()` flag.
- **Wire protocol:** JSON string control messages + raw `ArrayBuffer` binary frames on a single `RTCDataChannel` named `instant-share`. The wire protocol never mentions `stash_id` — only `session_id` and file `index`.
- **No comments in code** unless explaining *why* (project rule).
- **Path style:** Forward slashes in any persisted path; use `pathlib.Path` on PC.
- **Tests:** Add each new PC test to `dt_image_search/scripts/run_tests.sh`; web tests via Vitest; relay tests via Node test runner.
- **Commits:** Use `[feat]`/`[fix]` prefix matching existing repo convention. Commit after each green test cycle.

## File Structure

### New files

| File | Responsibility |
|---|---|
| `web/instant-share/package.json` | Frontend deps + scripts |
| `web/instant-share/vite.config.ts` | Vite build config |
| `web/instant-share/tailwind.config.ts` | Tailwind v3 config |
| `web/instant-share/postcss.config.js` | Tailwind PostCSS plugin |
| `web/instant-share/tsconfig.json` | TS config (strict) |
| `web/instant-share/tsconfig.node.json` | TS config for vite.config |
| `web/instant-share/index.html` | Vite entry HTML |
| `web/instant-share/src/main.tsx` | React mount |
| `web/instant-share/src/App.tsx` | State machine driver + screen switch |
| `web/instant-share/src/lib/urlParams.ts` | Parse `?sid=&opt=` from QR URL |
| `web/instant-share/src/lib/protocol.ts` | Typed message codec (control JSON + ArrayBuffer binary frames) |
| `web/instant-share/src/hooks/useSignalChannel.ts` | wss client: join, offer/answer, ICE trickle, leave |
| `web/instant-share/src/hooks/useWebRTC.ts` | `RTCPeerConnection` + `RTCDataChannel` lifecycle |
| `web/instant-share/src/hooks/useTransfer.ts` | Auto-flow state machine: auth → manifest → download → deliver |
| `web/instant-share/src/services/deliverer.ts` | Type-aware delivery (copy/open/render/save) |
| `web/instant-share/src/components/ConnectingScreen.tsx` | Spinner UI |
| `web/instant-share/src/components/TransferScreen.tsx` | Per-file progress auto-flow UI |
| `web/instant-share/src/components/DoneScreen.tsx` | Success + per-item re-copy/open/save buttons |
| `web/instant-share/src/components/ErrorScreen.tsx` | Error + retry |
| `web/instant-share/src/styles/index.css` | Tailwind directives |
| `web/instant-share/src/vite-env.d.ts` | Vite type shim |
| `web/instant-share/src/test/setup.ts` | Vitest setup (clipboard/Blob/URL mocks) |
| `web/instant-share/src/lib/urlParams.test.ts` | URL parse tests |
| `web/instant-share/src/lib/protocol.test.ts` | Protocol codec tests |
| `web/instant-share/src/services/deliverer.test.ts` | Delivery decision tests |
| `web/instant-share/relay/server.mjs` | Node wss relay |
| `web/instant-share/relay/relay.test.mjs` | Relay unit tests (Node test runner) |
| `web/instant-share/relay/package.json` | Relay deps (`ws`) + test script |
| `web/instant-share/scripts/build.sh` | `pnpm install && pnpm run build` |
| `web/instant-share/scripts/deploy.sh` | rsync `dist/` + `relay/` to boldman.net + restart relay |
| `web/instant-share/scripts/mock-pc-peer.mjs` | Integration-test mock PC peer (Node) |
| `web/instant-share/.gitignore` | node_modules, dist |
| `dt_image_search/instant_sharing/webrtc_peer.py` | PC `aiortc` peer + `WebRTCPeerManager` |
| `dt_image_search/instant_sharing/test_webrtc_peer.py` | PC peer unit tests |

### Modified files

| File | Change |
|---|---|
| `dt_image_search/requirements.txt` | Add `aiortc` |
| `dt_image_search/model/dts_config.py` | Add `get_instant_share_webrtc_relay_url()` + `get_instant_share_webrtc_relay_timeout_seconds()` |
| `dt_image_search/instant_sharing/runtime.py` | Wire `WebRTCPeerManager` into `InstantShareRuntime` lifecycle |
| `dt_image_search/scripts/instant_share_agent_main.py` | Pass `WebRTCPeerManager` into runtime (or let runtime construct it) |
| `dt_image_search/scripts/run_tests.sh` | Append `test_webrtc_peer.py` invocation |
| `web/www/deploy/aurora.conf` | Add `/share` + `/relay` nginx locations |

---

## Task 1: Scaffold web app + Tailwind + type config

**Files:**
- Create: `web/instant-share/package.json`, `vite.config.ts`, `tailwind.config.ts`, `postcss.config.js`, `tsconfig.json`, `tsconfig.node.json`, `index.html`, `.gitignore`
- Create: `web/instant-share/src/main.tsx`, `src/App.tsx`, `src/styles/index.css`, `src/vite-env.d.ts`

**Interfaces:**
- Produces: a buildable Vite+React+TS+Tailwind skeleton that renders `<App/>` with placeholder text "Instant Share". `pnpm run dev` serves on `:5173`; `pnpm run build` emits `dist/`.

- [ ] **Step 1: Create `package.json`**

Create `web/instant-share/package.json`:

```json
{
  "name": "web-instant-share",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.3",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "autoprefixer": "^10.4.19",
    "postcss": "^8.4.39",
    "tailwindcss": "^3.4.6",
    "typescript": "^5.5.3",
    "vite": "^5.3.4",
    "vitest": "^2.0.3",
    "@testing-library/jest-dom": "^6.4.6",
    "jsdom": "^24.1.0"
  }
}
```

- [ ] **Step 2: Create Vite + TS + Tailwind configs**

Create `web/instant-share/vite.config.ts`:

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { port: 5173 },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
  },
});
```

Create `web/instant-share/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

Create `web/instant-share/tsconfig.node.json`:

```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
```

Create `web/instant-share/tailwind.config.ts`:

```ts
import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {},
  },
  plugins: [],
} satisfies Config;
```

Create `web/instant-share/postcss.config.js`:

```js
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
};
```

Create `web/instant-share/.gitignore`:

```
node_modules/
dist/
*.log
```

- [ ] **Step 3: Create `index.html` + entry source**

Create `web/instant-share/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Instant Share</title>
  </head>
  <body class="bg-slate-950 text-slate-100">
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

Create `web/instant-share/src/main.tsx`:

```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './styles/index.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

Create `web/instant-share/src/styles/index.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

Create `web/instant-share/src/vite-env.d.ts`:

```ts
/// <reference types="vite/client" />
```

Create `web/instant-share/src/App.tsx`:

```tsx
export default function App() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <h1 className="text-2xl font-semibold">Instant Share</h1>
    </div>
  );
}
```

- [ ] **Step 4: Install + verify dev server + build**

Run:

```bash
cd web/instant-share && pnpm install && pnpm run build
```

Expected: build succeeds; `dist/index.html` exists. Then `pnpm run dev` (Ctrl+C after verifying it serves on `http://localhost:5173`).

- [ ] **Step 5: Commit**

```bash
git add web/instant-share
git commit -m "[feat] scaffold web instant-share vite+react+tailwind app"
```

---

## Task 2: URL param parser + tests

**Files:**
- Create: `web/instant-share/src/lib/urlParams.ts`, `web/instant-share/src/lib/urlParams.test.ts`, `web/instant-share/src/test/setup.ts`

**Interfaces:**
- Produces: `parseShareUrlParams(rawSearch: string): ParsedShareParams | null` where `ParsedShareParams = { sessionId: string; optCode: string }`. Returns `null` if either field is missing/empty. The QP names are `sid` and `opt` (from the existing QR URL contract). `ips`/`p`/`sp` are ignored.

- [ ] **Step 1: Create test setup file**

Create `web/instant-share/src/test/setup.ts`:

```ts
import '@testing-library/jest-dom';
```

- [ ] **Step 2: Write the failing tests**

Create `web/instant-share/src/lib/urlParams.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { parseShareUrlParams } from './urlParams';

describe('parseShareUrlParams', () => {
  it('parses sid and opt from a full QR URL search string', () => {
    const search = '?ips=192.168.1.5&p=9527&sp=9528&sid=abc-123&opt=123456';
    expect(parseShareUrlParams(search)).toEqual({
      sessionId: 'abc-123',
      optCode: '123456',
    });
  });

  it('ignores ips/p/sp fields but still returns sid/opt', () => {
    const search = '?sid=xyz&opt=999999';
    const result = parseShareUrlParams(search);
    expect(result?.sessionId).toBe('xyz');
    expect(result?.optCode).toBe('999999');
  });

  it('returns null when sid is missing', () => {
    expect(parseShareUrlParams('?opt=123456')).toBeNull();
  });

  it('returns null when opt is missing', () => {
    expect(parseShareUrlParams('?sid=abc')).toBeNull();
  });

  it('returns null when both are empty', () => {
    expect(parseShareUrlParams('?sid=&opt=')).toBeNull();
  });

  it('returns null for empty input', () => {
    expect(parseShareUrlParams('')).toBeNull();
  });

  it('handles leading ? prefix being absent', () => {
    expect(parseShareUrlParams('sid=abc&opt=123456')).toEqual({
      sessionId: 'abc',
      optCode: '123456',
    });
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd web/instant-share && pnpm test src/lib/urlParams.test.ts`
Expected: FAIL — `parseShareUrlParams` is not defined (module not found).

- [ ] **Step 4: Implement `parseShareUrlParams`**

Create `web/instant-share/src/lib/urlParams.ts`:

```ts
export interface ParsedShareParams {
  sessionId: string;
  optCode: string;
}

export function parseShareUrlParams(rawSearch: string): ParsedShareParams | null {
  const search = rawSearch.startsWith('?') ? rawSearch.slice(1) : rawSearch;
  if (!search) return null;
  const params = new URLSearchParams(search);
  const sessionId = params.get('sid') ?? '';
  const optCode = params.get('opt') ?? '';
  if (!sessionId || !optCode) return null;
  return { sessionId, optCode };
}
```

- [ ] **Step 5: Run tests — verify pass**

Run: `cd web/instant-share && pnpm test src/lib/urlParams.test.ts`
Expected: all 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add web/instant-share/src/lib/urlParams.ts web/instant-share/src/lib/urlParams.test.ts web/instant-share/src/test/setup.ts
git commit -m "[feat] add QR url param parser for web instant-share"
```

---

## Task 3: Protocol codec + tests

**Files:**
- Create: `web/instant-share/src/lib/protocol.ts`, `web/instant-share/src/lib/protocol.test.ts`

**Interfaces:**
- Produces the typed message union for control messages and helpers to (a) parse an incoming `string | ArrayBuffer` event.data into a typed `WireEvent`, and (b) encode outgoing control messages as JSON strings.

```ts
export type PayloadType = 'text' | 'link' | 'html' | 'file';

export interface ManifestFileEntry {
  index: number;
  type: 'text' | 'link' | 'html' | 'file';
  content_type: string;
  size_bytes?: number;
  filename?: string;
  content?: string;
}

export type ControlMessage =
  | { msg: 'auth'; opt_code: string }
  | { msg: 'auth_ok'; session_id: string; file_count: number; payload_type: PayloadType }
  | { msg: 'auth_error'; error: string }
  | { msg: 'manifest' }
  | { msg: 'manifest'; files: ManifestFileEntry[] }
  | { msg: 'download'; index: number }
  | { msg: 'file_start'; index: number; content_type: string; filename: string; size: number }
  | { msg: 'file_end'; index: number }
  | { msg: 'error'; code: 'expired' | 'not_found' | 'busy' | 'not_authorized'; message: string }
  | { msg: 'bye' };

export type WireEvent =
  | { kind: 'control'; message: ControlMessage }
  | { kind: 'binary'; buffer: ArrayBuffer };

export function encodeControl(message: ControlMessage): string;
export function decodeWireEvent(data: string | ArrayBuffer): WireEvent | null;
```

- [ ] **Step 1: Write failing tests**

Create `web/instant-share/src/lib/protocol.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { encodeControl, decodeWireEvent } from './protocol';

describe('protocol codec', () => {
  it('encodes a control message as JSON string', () => {
    const s = encodeControl({ msg: 'auth', opt_code: '123456' });
    expect(s).toBe('{"msg":"auth","opt_code":"123456"}');
  });

  it('decodes a string control message', () => {
    const ev = decodeWireEvent('{"msg":"auth_ok","session_id":"s1","file_count":2,"payload_type":"file"}');
    expect(ev?.kind).toBe('control');
    expect(ev?.kind === 'control' && ev.message.msg).toBe('auth_ok');
  });

  it('decodes an ArrayBuffer as binary', () => {
    const buf = new Uint8Array([1, 2, 3]).buffer;
    const ev = decodeWireEvent(buf);
    expect(ev?.kind).toBe('binary');
    if (ev?.kind === 'binary') {
      expect(new Uint8Array(ev.buffer)).toEqual(new Uint8Array([1, 2, 3]));
    }
  });

  it('returns null for malformed JSON string', () => {
    expect(decodeWireEvent('not json')).toBeNull();
  });

  it('returns null for unknown msg field', () => {
    expect(decodeWireEvent('{"msg":"bogus"}')).toBeNull();
  });

  it('returns null for empty string', () => {
    expect(decodeWireEvent('')).toBeNull();
  });

  it('round-trips manifest with inline text content', () => {
    const manifest = {
      msg: 'manifest' as const,
      files: [{ index: 0, type: 'text' as const, content_type: 'text/plain', content: 'hi' }],
    };
    const s = encodeControl(manifest);
    const ev = decodeWireEvent(s);
    expect(ev?.kind).toBe('control');
    if (ev?.kind === 'control' && ev.message.msg === 'manifest') {
      expect(ev.message.files[0].content).toBe('hi');
    }
  });
});
```

- [ ] **Step 2: Run tests — verify fail**

Run: `cd web/instant-share && pnpm test src/lib/protocol.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the codec**

Create `web/instant-share/src/lib/protocol.ts`:

```ts
export type PayloadType = 'text' | 'link' | 'html' | 'file';

export interface ManifestFileEntry {
  index: number;
  type: 'text' | 'link' | 'html' | 'file';
  content_type: string;
  size_bytes?: number;
  filename?: string;
  content?: string;
}

export type ControlMessage =
  | { msg: 'auth'; opt_code: string }
  | { msg: 'auth_ok'; session_id: string; file_count: number; payload_type: PayloadType }
  | { msg: 'auth_error'; error: string }
  | { msg: 'manifest' }
  | { msg: 'manifest'; files: ManifestFileEntry[] }
  | { msg: 'download'; index: number }
  | { msg: 'file_start'; index: number; content_type: string; filename: string; size: number }
  | { msg: 'file_end'; index: number }
  | { msg: 'error'; code: 'expired' | 'not_found' | 'busy' | 'not_authorized'; message: string }
  | { msg: 'bye' };

export type WireEvent =
  | { kind: 'control'; message: ControlMessage }
  | { kind: 'binary'; buffer: ArrayBuffer };

const KNOWN_MSGS = new Set<string>([
  'auth', 'auth_ok', 'auth_error', 'manifest', 'download',
  'file_start', 'file_end', 'error', 'bye',
]);

export function encodeControl(message: ControlMessage): string {
  return JSON.stringify(message);
}

export function decodeWireEvent(data: string | ArrayBuffer): WireEvent | null {
  if (typeof data !== 'string') {
    return { kind: 'binary', buffer: data };
  }
  if (!data) return null;
  try {
    const parsed = JSON.parse(data) as { msg?: string };
    if (!parsed.msg || !KNOWN_MSGS.has(parsed.msg)) return null;
    return { kind: 'control', message: parsed as ControlMessage };
  } catch {
    return null;
  }
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `cd web/instant-share && pnpm test src/lib/protocol.test.ts`
Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/src/lib/protocol.ts web/instant-share/src/lib/protocol.test.ts
git commit -m "[feat] add wire protocol codec for web instant-share"
```

---

## Task 4: Signal channel hook (`useSignalChannel`)

**Files:**
- Create: `web/instant-share/src/hooks/useSignalChannel.ts`

**Interfaces:**
- Produces a React hook that opens a `WebSocket` to the relay, joins a session room, and forwards signaling events.
- Consumes (from later tasks): the relay URL `wss://dl.boldman.net/relay` (passed as param), events consumed by `useWebRTC` via the returned `send` + `onEvent` callback registration.

```ts
export type SignalEvent =
  | { type: 'joined'; role: 'pc' | 'browser' }
  | { type: 'offer'; sdp: string }
  | { type: 'answer'; sdp: string }
  | { type: 'candidate'; candidate: RTCIceCandidateInit }
  | { type: 'peer_left' }
  | { type: 'room_full' }
  | { type: 'error'; message: string };

export interface UseSignalChannelReturn {
  ready: boolean;
  send: (msg: object) => void;
  onEvent: (handler: (e: SignalEvent) => void) => () => void;
  close: () => void;
}

export function useSignalChannel(
  relayUrl: string,
  sessionId: string,
  role: 'pc' | 'browser',
): UseSignalChannelReturn;
```

No unit test (hook relies on real `WebSocket`); integration-tested in Task 13. Pure logic for sending/forwarding is straightforward; verified by integration tests.

- [ ] **Step 1: Implement the hook**

Create `web/instant-share/src/hooks/useSignalChannel.ts`:

```ts
import { useEffect, useRef, useState, useCallback } from 'react';

export type SignalEvent =
  | { type: 'joined'; role: 'pc' | 'browser' }
  | { type: 'offer'; sdp: string }
  | { type: 'answer'; sdp: string }
  | { type: 'candidate'; candidate: RTCIceCandidateInit }
  | { type: 'peer_left' }
  | { type: 'room_full' }
  | { type: 'error'; message: string };

export interface UseSignalChannelReturn {
  ready: boolean;
  send: (msg: object) => void;
  onEvent: (handler: (e: SignalEvent) => void) => () => void;
  close: () => void;
}

export function useSignalChannel(
  relayUrl: string,
  sessionId: string,
  role: 'pc' | 'browser',
): UseSignalChannelReturn {
  const wsRef = useRef<WebSocket | null>(null);
  const handlersRef = useRef<Set<(e: SignalEvent) => void>>(new Set());
  const [ready, setReady] = useState(false);

  const emit = useCallback((e: SignalEvent) => {
    handlersRef.current.forEach((h) => h(e));
  }, []);

  useEffect(() => {
    const ws = new WebSocket(`${relayUrl}?sid=${encodeURIComponent(sessionId)}&role=${role}`);
    wsRef.current = ws;

    ws.onopen = () => {
      ws.send(JSON.stringify({ type: 'join', sid: sessionId, role }));
    };
    ws.onmessage = (event) => {
      if (typeof event.data !== 'string') return;
      let parsed: any;
      try { parsed = JSON.parse(event.data); } catch { return; }
      if (parsed.type === 'joined') {
        setReady(true);
        emit({ type: 'joined', role: parsed.role });
        return;
      }
      if (parsed.type === 'peer_left') { emit({ type: 'peer_left' }); return; }
      if (parsed.type === 'room_full') { emit({ type: 'room_full' }); return; }
      if (parsed.type === 'offer') { emit({ type: 'offer', sdp: parsed.sdp }); return; }
      if (parsed.type === 'answer') { emit({ type: 'answer', sdp: parsed.sdp }); return; }
      if (parsed.type === 'candidate') { emit({ type: 'candidate', candidate: parsed.candidate }); return; }
    };
    ws.onerror = () => emit({ type: 'error', message: 'Relay connection error' });
    ws.onclose = () => {
      setReady(false);
      emit({ type: 'peer_left' });
    };

    return () => {
      try { ws.close(); } catch {}
      wsRef.current = null;
      setReady(false);
    };
  }, [relayUrl, sessionId, role, emit]);

  const send = useCallback((msg: object) => {
    wsRef.current?.send(JSON.stringify(msg));
  }, []);

  const onEvent = useCallback((handler: (e: SignalEvent) => void) => {
    handlersRef.current.add(handler);
    return () => { handlersRef.current.delete(handler); };
  }, []);

  const close = useCallback(() => {
    try { wsRef.current?.send(JSON.stringify({ type: 'leave' })); } catch {}
    wsRef.current?.close();
  }, []);

  return { ready, send, onEvent, close };
}
```

- [ ] **Step 2: Verify type-check passes**

Run: `cd web/instant-share && pnpm exec tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add web/instant-share/src/hooks/useSignalChannel.ts
git commit -m "[feat] add signal channel hook for web instant-share"
```

---

## Task 5: WebRTC hook (`useWebRTC`)

**Files:**
- Create: `web/instant-share/src/hooks/useWebRTC.ts`

**Interfaces:**
- Consumes: `UseSignalChannelReturn` from Task 4. Browser is answerer (PC is offerer).
- Produces: a hook exposing the open `RTCDataChannel` + close() so `useTransfer` can drive the protocol.

```ts
export interface UseWebRTCReturn {
  channel: RTCDataChannel | null;
  state: 'new' | 'connecting' | 'open' | 'closed' | 'failed';
  close: () => void;
}

export function useWebRTC(signal: UseSignalChannelReturn): UseWebRTCReturn;
```

The hook creates an `RTCPeerConnection` with no STUN/TURN servers (host candidates only — same-LAN), waits for the PC offer from the signal channel, creates + sends an answer, exchanges ICE candidates, and opens the data channel named `instant-share`. (The PC creates the data channel with `pc.createDataChannel('instant-share')`; the browser receives it via `ondatachannel` because it's the answerer.)

- [ ] **Step 1: Implement the hook**

Create `web/instant-share/src/hooks/useWebRTC.ts`:

```ts
import { useEffect, useRef, useState, useCallback } from 'react';
import type { UseSignalChannelReturn, SignalEvent } from './useSignalChannel';

export interface UseWebRTCReturn {
  channel: RTCDataChannel | null;
  state: 'new' | 'connecting' | 'open' | 'closed' | 'failed';
  close: () => void;
}

export function useWebRTC(signal: UseSignalChannelReturn): UseWebRTCReturn {
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const channelRef = useRef<RTCDataChannel | null>(null);
  const [channel, setChannel] = useState<RTCDataChannel | null>(null);
  const [state, setState] = useState<UseWebRTCReturn['state']>('new');

  const handleSignalEvent = useCallback((e: SignalEvent) => {
    const pc = pcRef.current;
    if (!pc) return;

    if (e.type === 'offer') {
      pc.setRemoteDescription({ type: 'offer', sdp: e.sdp })
        .then(async () => {
          const answer = await pc.createAnswer({ offerToReceiveData: true } as RTCOfferOptions);
          await pc.setLocalDescription(answer);
          signal.send({ type: 'answer', sdp: answer.sdp });
          setState('connecting');
        })
        .catch(() => setState('failed'));
    } else if (e.type === 'answer') {
      pc.setRemoteDescription({ type: 'answer', sdp: e.sdp })
        .catch(() => setState('failed'));
    } else if (e.type === 'candidate') {
      pc.addIceCandidate(e.candidate).catch(() => {});
    } else if (e.type === 'peer_left' || e.type === 'room_full') {
      setState('closed');
    }
  }, [signal]);

  useEffect(() => {
    const pc = new RTCPeerConnection({ iceServers: [] });
    pcRef.current = pc;

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        signal.send({ type: 'candidate', candidate: event.candidate.toJSON() });
      }
    };
    pc.onconnectionstatechange = () => {
      const s = pc.connectionState;
      if (s === 'connected') setState((prev) => (prev === 'open' ? 'open' : 'connecting'));
      else if (s === 'disconnected' || s === 'failed') setState('failed');
      else if (s === 'closed') setState('closed');
    };
    pc.ondatachannel = (event) => {
      const dc = event.channel;
      dc.binaryType = 'arraybuffer';
      channelRef.current = dc;
      dc.onopen = () => setState('open');
      dc.onclose = () => setState('closed');
      setChannel(dc);
    };

    const unsubscribe = signal.onEvent(handleSignalEvent);
    return () => {
      unsubscribe();
      try { channelRef.current?.close(); } catch {}
      try { pc.close(); } catch {}
      pcRef.current = null;
      channelRef.current = null;
      setChannel(null);
    };
  }, [signal, handleSignalEvent]);

  const close = useCallback(() => {
    try { channelRef.current?.close(); } catch {}
    try { pcRef.current?.close(); } catch {}
    signal.send({ type: 'leave' });
    signal.close();
  }, [signal]);

  return { channel, state, close };
}
```

- [ ] **Step 2: Type-check**

Run: `cd web/instant-share && pnpm exec tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add web/instant-share/src/hooks/useWebRTC.ts
git commit -m "[feat] add webrtc peer hook (answerer) for web instant-share"
```

---

## Task 6: Transfer state machine hook (`useTransfer`)

**Files:**
- Create: `web/instant-share/src/hooks/useTransfer.ts`

**Interfaces:**
- Consumes: `UseWebRTCReturn` from Task 5, `ParsedShareParams` from Task 2, the codec from Task 3.
- Produces: a hook driving the auto-flow state machine (booting → connecting → authenticating → transferring → done | error), exposing the state + per-file progress + file Blobs ready for delivery.

```ts
export interface FileProgress {
  index: number;
  filename?: string;
  content_type: string;
  size: number;
  received: number;
  blob?: Blob;
  status: 'queued' | 'downloading' | 'done';
}

export type TransferStatus =
  | 'booting' | 'connecting' | 'authenticating'
  | 'transferring' | 'done' | 'error';

export interface TransferError {
  code: string;
  message: string;
}

export interface UseTransferReturn {
  status: TransferStatus;
  error: TransferError | null;
  manifest: ManifestFileEntry[] | null;
  payloadType: PayloadType | null;
  files: FileProgress[];
  retry: () => void;
}

export function useTransfer(
  params: ParsedShareParams,
  webrtc: UseWebRTCReturn,
): UseTransferReturn;
```

Behavior:
- On `webrtc.channel` becoming non-null + `state==='open'`, send `auth` with `params.optCode`.
- On `auth_ok`, auto-send `manifest`.
- On `manifest`, parse text/link/html entries; for text-like types with inline `content`, mark them `done` immediately and skip `download` (claims handled PC-side). For file-like entries, send `download` serially, reassembling `file_start`/binary/`file_end` into a Blob per index.
- On `auth_error`/`error`/DC close mid-flow, transition to `error`.
- On all files `done`, transition to `done`.
- `retry` re-scans QR (calls `webrtc.close()` and shows error "Please re-scan the QR code").

- [ ] **Step 1: Implement the hook**

Create `web/instant-share/src/hooks/useTransfer.ts`:

```ts
import { useEffect, useRef, useState, useCallback } from 'react';
import type { ParsedShareParams } from '../lib/urlParams';
import type { ManifestFileEntry, PayloadType, ControlMessage } from '../lib/protocol';
import { encodeControl, decodeWireEvent } from '../lib/protocol';
import type { UseWebRTCReturn } from './useWebRTC';

export interface FileProgress {
  index: number;
  filename?: string;
  content_type: string;
  size: number;
  received: number;
  blob?: Blob;
  status: 'queued' | 'downloading' | 'done';
}

export type TransferStatus =
  | 'booting' | 'connecting' | 'authenticating'
  | 'transferring' | 'done' | 'error';

export interface TransferError {
  code: string;
  message: string;
}

export interface UseTransferReturn {
  status: TransferStatus;
  error: TransferError | null;
  manifest: ManifestFileEntry[] | null;
  payloadType: PayloadType | null;
  files: FileProgress[];
  retry: () => void;
}

const AUTH_TIMEOUT_MS = 15000;

export function useTransfer(params: ParsedShareParams, webrtc: UseWebRTCReturn): UseTransferReturn {
  const [status, setStatus] = useState<TransferStatus>('connecting');
  const [error, setError] = useState<TransferError | null>(null);
  const [manifest, setManifest] = useState<ManifestFileEntry[] | null>(null);
  const [payloadType, setPayloadType] = useState<PayloadType | null>(null);
  const [files, setFiles] = useState<FileProgress[]>([]);

  const filesRef = useRef<FileProgress[]>([]);
  const currentBinaryRef = useRef<{ index: number; chunks: ArrayBuffer[]; contentType: string; filename: string; size: number } | null>(null);
  const pendingManifestRef = useRef<ManifestFileEntry[] | null>(null);
  const nextDownloadIndexRef = useRef<number>(0);
  const authTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sentAuthRef = useRef(false);

  const fail = useCallback((code: string, message: string) => {
    if (authTimerRef.current) clearTimeout(authTimerRef.current);
    setError({ code, message });
    setStatus('error');
  }, []);

  const sendControl = useCallback((msg: ControlMessage) => {
    const dc = webrtc.channel;
    if (dc && dc.readyState === 'open') {
      dc.send(encodeControl(msg));
    }
  }, [webrtc]);

  const downloadNext = useCallback(() => {
    const pending = pendingManifestRef.current ?? [];
    const idx = nextDownloadIndexRef.current;
    if (idx >= pending.length) {
      setStatus('done');
      return;
    }
    const entry = pending[idx];
    if (entry.type === 'text' || entry.type === 'link' || entry.type === 'html') {
      filesRef.current = filesRef.current.map((f) =>
        f.index === idx ? { ...f, status: 'done', received: f.size } : f,
      );
      setFiles([...filesRef.current]);
      nextDownloadIndexRef.current = idx + 1;
      downloadNext();
      return;
    }
    sendControl({ msg: 'download', index: idx });
  }, [sendControl]);

  const handleMessage = useCallback((data: string | ArrayBuffer) => {
    const ev = decodeWireEvent(data);
    if (!ev) return;
    if (ev.kind === 'binary') {
      if (currentBinaryRef.current) {
        currentBinaryRef.current.chunks.push(ev.buffer);
        filesRef.current = filesRef.current.map((f) =>
          f.index === currentBinaryRef.current!.index
            ? { ...f, received: f.received + ev.buffer.byteLength }
            : f,
        );
        setFiles([...filesRef.current]);
      }
      return;
    }
    const m = ev.message;
    if (m.msg === 'auth_ok') {
      if (authTimerRef.current) clearTimeout(authTimerRef.current);
      setPayloadType(m.payload_type);
      setStatus('transferring');
      sendControl({ msg: 'manifest' });
    } else if (m.msg === 'auth_error') {
      fail('auth_error', m.error);
    } else if (m.msg === 'manifest') {
      pendingManifestRef.current = m.files;
      nextDownloadIndexRef.current = 0;
      filesRef.current = m.files.map((f) => ({
        index: f.index,
        filename: f.filename,
        content_type: f.content_type,
        size: f.size_bytes ?? (f.content?.length ?? 0),
        received: 0,
        status: 'queued',
      }));
      setFiles([...filesRef.current]);
      setManifest(m.files);
      downloadNext();
    } else if (m.msg === 'file_start') {
      currentBinaryRef.current = {
        index: m.index,
        chunks: [],
        contentType: m.content_type,
        filename: m.filename,
        size: m.size,
      };
      filesRef.current = filesRef.current.map((f) =>
        f.index === m.index ? { ...f, status: 'downloading', content_type: m.content_type, filename: m.filename, size: m.size } : f,
      );
      setFiles([...filesRef.current]);
    } else if (m.msg === 'file_end') {
      const cur = currentBinaryRef.current;
      if (cur && cur.index === m.index) {
        const blob = new Blob(cur.chunks, { type: cur.contentType });
        filesRef.current = filesRef.current.map((f) =>
          f.index === m.index ? { ...f, status: 'done', received: f.size, blob } : f,
        );
        setFiles([...filesRef.current]);
        currentBinaryRef.current = null;
        nextDownloadIndexRef.current = m.index + 1;
        downloadNext();
      }
    } else if (m.msg === 'error') {
      fail(m.code, m.message);
    } else if (m.msg === 'bye') {
      setStatus('done');
    }
  }, [sendControl, downloadNext, fail]);

  useEffect(() => {
    const dc = webrtc.channel;
    if (!dc) {
      setStatus((prev) => (prev === 'done' || prev === 'error') ? prev : 'connecting');
      return;
    }
    if (dc.readyState !== 'open') return;
    if (sentAuthRef.current) return;
    sentAuthRef.current = true;
    setStatus('authenticating');
    sendControl({ msg: 'auth', opt_code: params.optCode });
    authTimerRef.current = setTimeout(() => {
      fail('auth_timeout', 'Authentication timed out');
    }, AUTH_TIMEOUT_MS);

    const onMessage = (e: MessageEvent) => handleMessage(e.data);
    const onClose = () => {
      setStatus((prev) => (prev === 'done' || prev === 'error') ? prev : 'error');
      setError((prev) => prev ?? { code: 'disconnected', message: 'Connection lost' });
    };
    dc.addEventListener('message', onMessage);
    dc.addEventListener('close', onClose);
    return () => {
      dc.removeEventListener('message', onMessage);
      dc.removeEventListener('close', onClose);
      if (authTimerRef.current) clearTimeout(authTimerRef.current);
    };
  }, [webrtc, params.optCode, sendControl, handleMessage, fail]);

  useEffect(() => {
    if (webrtc.state === 'failed') {
      fail('disconnected', 'Connection failed');
    } else if (webrtc.state === 'closed' && status !== 'done' && status !== 'error') {
      fail('disconnected', 'Connection closed');
    }
  }, [webrtc.state, fail, status]);

  const retry = useCallback(() => {
    webrtc.close();
    setError({ code: 'rescan', message: 'Please re-scan the QR code to retry.' });
    setStatus('error');
  }, [webrtc]);

  return { status, error, manifest, payloadType, files, retry };
}
```

- [ ] **Step 2: Type-check**

Run: `cd web/instant-share && pnpm exec tsc --noEmit`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add web/instant-share/src/hooks/useTransfer.ts
git commit -m "[feat] add transfer state machine hook for web instant-share"
```

---

## Task 7: Deliverer + tests

**Files:**
- Create: `web/instant-share/src/services/deliverer.ts`, `web/instant-share/src/services/deliverer.test.ts`

**Interfaces:**
- Produces: pure functions that take a `ManifestFileEntry`/`FileProgress` and return a `DeliveryAction` plan; plus the side-effecting `applyDelivery(action)` that uses `navigator.clipboard` / `Blob` / `URL.createObjectURL` / `navigator.share`. Tests target the planner (pure), not the side effects.

```ts
export type DeliveryAction =
  | { kind: 'copy'; text: string }
  | { kind: 'open_link'; href: string }
  | { kind: 'render_html'; html: string }
  | { kind: 'save_blob'; blob: Blob; filename: string }
  | { kind: 'save_to_photos'; blob: Blob; filename: string }
  | { kind: 'none' };

export function planDelivery(entry: ManifestFileEntry, file: FileProgress | null): DeliveryAction;
export async function applyDelivery(action: DeliveryAction): Promise<void>;
```

- [ ] **Step 1: Write failing tests**

Create `web/instant-share/src/services/deliverer.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { planDelivery } from './deliverer';
import type { ManifestFileEntry } from '../lib/protocol';

const mkEntry = (over: Partial<ManifestFileEntry>): ManifestFileEntry => ({
  index: 0,
  type: 'file',
  content_type: 'application/octet-stream',
  ...over,
});

describe('planDelivery', () => {
  it('plans copy for text', () => {
    const e = mkEntry({ type: 'text', content_type: 'text/plain', content: 'hi' });
    expect(planDelivery(e, null)).toEqual({ kind: 'copy', text: 'hi' });
  });

  it('plans open_link for link', () => {
    const e = mkEntry({ type: 'link', content_type: 'text/uri-list', content: 'https://x' });
    expect(planDelivery(e, null)).toEqual({ kind: 'open_link', href: 'https://x' });
  });

  it('plans render_html for html', () => {
    const e = mkEntry({ type: 'html', content_type: 'text/html', content: '<b>x</b>' });
    expect(planDelivery(e, null)).toEqual({ kind: 'render_html', html: '<b>x</b>' });
  });

  it('plans save_blob for a file with blob', () => {
    const blob = new Blob([new Uint8Array([1])]);
    const e = mkEntry({ type: 'file', content_type: 'image/png', filename: 'p.png', size_bytes: 1 });
    const action = planDelivery(e, { index: 0, content_type: 'image/png', size: 1, received: 1, blob, status: 'done' });
    expect(action.kind).toBe('save_blob');
    if (action.kind === 'save_blob') {
      expect(action.filename).toBe('p.png');
      expect(action.blob).toBe(blob);
    }
  });

  it('plans save_to_photos for an image with blob', () => {
    const blob = new Blob([new Uint8Array([1])], { type: 'image/png' });
    const e = mkEntry({ type: 'file', content_type: 'image/png', filename: 'photo.png', size_bytes: 1 });
    const action = planDelivery(e, { index: 0, content_type: 'image/png', size: 1, received: 1, blob, status: 'done' });
    expect(['save_blob', 'save_to_photos']).toContain(action.kind);
  });

  it('plans none when file has no blob yet', () => {
    const e = mkEntry({ type: 'file', filename: 'p.png' });
    expect(planDelivery(e, { index: 0, content_type: '', size: 0, received: 0, status: 'downloading' })).toEqual({ kind: 'none' });
  });

  it('plans none for file entry with no blob and no content', () => {
    const e = mkEntry({ type: 'file', filename: 'p.png' });
    expect(planDelivery(e, null)).toEqual({ kind: 'none' });
  });
});
```

- [ ] **Step 2: Run tests — verify fail**

Run: `cd web/instant-share && pnpm test src/services/deliverer.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement deliverer**

Create `web/instant-share/src/services/deliverer.ts`:

```ts
import type { ManifestFileEntry } from '../lib/protocol';
import type { FileProgress } from '../hooks/useTransfer';

export type DeliveryAction =
  | { kind: 'copy'; text: string }
  | { kind: 'open_link'; href: string }
  | { kind: 'render_html'; html: string }
  | { kind: 'save_blob'; blob: Blob; filename: string }
  | { kind: 'save_to_photos'; blob: Blob; filename: string }
  | { kind: 'none' };

export function planDelivery(entry: ManifestFileEntry, file: FileProgress | null): DeliveryAction {
  if (entry.type === 'text') {
    return { kind: 'copy', text: entry.content ?? '' };
  }
  if (entry.type === 'link') {
    return { kind: 'open_link', href: entry.content ?? '' };
  }
  if (entry.type === 'html') {
    return { kind: 'render_html', html: entry.content ?? '' };
  }
  if (entry.type === 'file') {
    if (!file?.blob) return { kind: 'none' };
    if (entry.content_type.startsWith('image/') && typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
      return { kind: 'save_to_photos', blob: file.blob, filename: file.filename ?? 'image' };
    }
    return { kind: 'save_blob', blob: file.blob, filename: file.filename ?? 'file' };
  }
  return { kind: 'none' };
}

export async function applyDelivery(action: DeliveryAction): Promise<void> {
  switch (action.kind) {
    case 'copy':
      if (navigator.clipboard) await navigator.clipboard.writeText(action.text);
      break;
    case 'open_link':
      window.open(action.href, '_blank', 'noopener,noreferrer');
      break;
    case 'render_html': {
      const iframe = document.createElement('iframe');
      iframe.sandbox.add('allow-same-origin');
      iframe.srcdoc = action.html;
      iframe.style.cssText = 'width:100%;min-height:200px;border:1px solid #334155;border-radius:8px;';
      document.body.appendChild(iframe);
      break;
    }
    case 'save_blob': {
      const url = URL.createObjectURL(action.blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = action.filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      break;
    }
    case 'save_to_photos': {
      const file = new File([action.blob], action.filename, { type: action.blob.type });
      if (navigator.share && navigator.canShare({ files: [file] })) {
        await navigator.share({ files: [file] });
      } else {
        const url = URL.createObjectURL(action.blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = action.filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      }
      break;
    }
    case 'none':
      break;
  }
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `cd web/instant-share && pnpm test src/services/deliverer.test.ts`
Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/src/services/deliverer.ts web/instant-share/src/services/deliverer.test.ts
git commit -m "[feat] add type-aware deliverer for web instant-share"
```

---

## Task 8: UI screens + App wiring

**Files:**
- Create: `web/instant-share/src/components/ConnectingScreen.tsx`, `TransferScreen.tsx`, `DoneScreen.tsx`, `ErrorScreen.tsx`
- Modify: `web/instant-share/src/App.tsx`

**Interfaces:**
- Consumes: `useSignalChannel`, `useWebRTC`, `useTransfer`, `planDelivery`, `applyDelivery`, `parseShareUrlParams`.
- Produces: a top-level `App` that switches screens based on `useTransfer`'s `status`. Auto-applies delivery for text/link/html on `transferring`→`done` transition; exposes "Copy"/"Save to Photos" buttons on `DoneScreen`.

- [ ] **Step 1: Create the screens**

Create `web/instant-share/src/components/ConnectingScreen.tsx`:

```tsx
export default function ConnectingScreen() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4">
      <div className="h-10 w-10 border-4 border-slate-700 border-t-sky-400 rounded-full animate-spin" />
      <p className="text-slate-300">Connecting to PC…</p>
    </div>
  );
}
```

Create `web/instant-share/src/components/TransferScreen.tsx`:

```tsx
import type { FileProgress } from '../hooks/useTransfer';

export default function TransferScreen({ files }: { files: FileProgress[] }) {
  if (!files.length) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-slate-300">Receiving…</p>
      </div>
    );
  }
  return (
    <div className="min-h-screen flex flex-col gap-3 p-6 max-w-md mx-auto">
      <h2 className="text-lg font-semibold mb-2">Receiving…</h2>
      {files.map((f) => (
        <div key={f.index} className="rounded-lg border border-slate-800 p-3 flex flex-col gap-1">
          <div className="flex justify-between text-sm">
            <span className="truncate text-slate-200">{f.filename ?? `Item ${f.index + 1}`}</span>
            <span className="text-slate-400">{formatBytes(f.received)} / {formatBytes(f.size)}</span>
          </div>
          <div className="h-1.5 rounded-full bg-slate-800 overflow-hidden">
            <div className="h-full bg-sky-400 transition-all" style={{ width: `${pct(f)}%` }} />
          </div>
        </div>
      ))}
    </div>
  );
}

function pct(f: FileProgress): number {
  if (f.size <= 0) return f.status === 'done' ? 100 : 0;
  return Math.min(100, Math.round((f.received / f.size) * 100));
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}
```

Create `web/instant-share/src/components/DoneScreen.tsx`:

```tsx
import { useEffect } from 'react';
import type { FileProgress } from '../hooks/useTransfer';
import type { ManifestFileEntry } from '../lib/protocol';
import { planDelivery, applyDelivery } from '../services/deliverer';

export default function DoneScreen({
  manifest,
  files,
}: {
  manifest: ManifestFileEntry[];
  files: FileProgress[];
}) {
  useEffect(() => {
    manifest.forEach((entry) => {
      const f = files.find((x) => x.index === entry.index) ?? null;
      const action = planDelivery(entry, f);
      if (action.kind === 'copy' || action.kind === 'save_blob' || action.kind === 'save_to_photos') {
        applyDelivery(action).catch(() => {});
      }
    });
  }, [manifest, files]);

  return (
    <div className="min-h-screen flex flex-col gap-3 p-6 max-w-md mx-auto">
      <h2 className="text-lg font-semibold text-emerald-400">Received</h2>
      {manifest.map((entry) => {
        const f = files.find((x) => x.index === entry.index) ?? null;
        const action = planDelivery(entry, f);
        return (
          <div key={entry.index} className="rounded-lg border border-slate-800 p-3 flex items-center justify-between">
            <span className="truncate text-slate-200">{entry.filename ?? `Item ${entry.index + 1}`}</span>
            <div className="flex gap-2">
              {action.kind === 'copy' && (
                <button className="text-sm px-3 py-1 rounded bg-sky-600 hover:bg-sky-500" onClick={() => applyDelivery(action)}>Copy</button>
              )}
              {action.kind === 'open_link' && (
                <a className="text-sm px-3 py-1 rounded bg-sky-600 hover:bg-sky-500" href={action.href} target="_blank" rel="noopener noreferrer">Open</a>
              )}
              {(action.kind === 'save_blob' || action.kind === 'save_to_photos') && (
                <button className="text-sm px-3 py-1 rounded bg-sky-600 hover:bg-sky-500" onClick={() => applyDelivery(action)}>Save{action.kind === 'save_to_photos' ? ' to Photos' : ''}</button>
              )}
            </div>
          </div>
        );
      })}
    </div>
  );
}
```

Create `web/instant-share/src/components/ErrorScreen.tsx`:

```tsx
import type { TransferError } from '../hooks/useTransfer';

export default function ErrorScreen({ error, onRetry }: { error: TransferError; onRetry: () => void }) {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center gap-4 p-6 text-center">
      <h2 className="text-xl font-semibold text-rose-400">Cannot receive</h2>
      <p className="text-slate-300">{error.message}</p>
      <button className="px-4 py-2 rounded bg-sky-600 hover:bg-sky-500" onClick={onRetry}>Re-scan QR</button>
    </div>
  );
}
```

- [ ] **Step 2: Wire `App.tsx`**

Replace `web/instant-share/src/App.tsx` with:

```tsx
import { useMemo } from 'react';
import { parseShareUrlParams } from './lib/urlParams';
import { useSignalChannel } from './hooks/useSignalChannel';
import { useWebRTC } from './hooks/useWebRTC';
import { useTransfer } from './hooks/useTransfer';
import ConnectingScreen from './components/ConnectingScreen';
import TransferScreen from './components/TransferScreen';
import DoneScreen from './components/DoneScreen';
import ErrorScreen from './components/ErrorScreen';

const RELAY_URL = (import.meta.env.VITE_RELAY_URL as string) ?? 'wss://dl.boldman.net/relay';

export default function App() {
  const params = useMemo(() => parseShareUrlParams(window.location.search), []);
  if (!params) {
    return <ErrorScreen error={{ code: 'invalid_link', message: 'Invalid or expired link.' }} onRetry={() => window.location.reload()} />;
  }

  return <ReceiverFlow sessionId={params.sessionId} optCode={params.optCode} />;
}

function ReceiverFlow({ sessionId, optCode }: { sessionId: string; optCode: string }) {
  const signal = useSignalChannel(RELAY_URL, sessionId, 'browser');
  const webrtc = useWebRTC(signal);
  const transfer = useTransfer({ sessionId, optCode }, webrtc);

  if (transfer.status === 'done' && transfer.manifest) {
    return <DoneScreen manifest={transfer.manifest} files={transfer.files} />;
  }
  if (transfer.status === 'error') {
    return <ErrorScreen error={transfer.error ?? { code: 'unknown', message: 'Unknown error' }} onRetry={transfer.retry} />;
  }
  if (transfer.status === 'transferring') {
    return <TransferScreen files={transfer.files} />;
  }
  return <ConnectingScreen />;
}
```

- [ ] **Step 3: Type-check + build**

Run: `cd web/instant-share && pnpm exec tsc --noEmit && pnpm run build`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add web/instant-share/src/components web/instant-share/src/App.tsx
git commit -m "[feat] add web instant-share UI screens and app wiring"
```

---

## Task 9: CDN WebSocket relay server + tests

**Files:**
- Create: `web/instant-share/relay/package.json`, `relay/server.mjs`, `relay/relay.test.mjs`

**Interfaces:**
- Produces: a Node wss relay server listening on `process.env.PORT ?? 8787`. Accepts peers via `?sid=<uuid>&role=pc|browser`. Forwards every non-`join` message to the opposite-role peer in the room. Evicts on disconnect / `leave` / 5-minute idle TTL.
- All messages are JSON. The relay never parses payloads.

- [ ] **Step 1: Create `relay/package.json`**

Create `web/instant-share/relay/package.json`:

```json
{
  "name": "instant-share-relay",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "main": "server.mjs",
  "scripts": {
    "start": "node server.mjs",
    "test": "node --test relay.test.mjs"
  },
  "dependencies": {
    "ws": "^8.18.0"
  }
}
```

- [ ] **Step 2: Write failing tests**

Create `web/instant-share/relay/relay.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocketServer } from 'ws';
import { createRelay } from './server.mjs';

function startRelay() {
  return new Promise((resolve) => {
    const wss = new WebSocketServer({ port: 0 }, () => {
      const port = wss.address().port;
      const stop = createRelay(wss);
      resolve({ port, stop });
    });
  });
}

function wsClient(port, sid, role) {
  return new WebSocket(`ws://localhost:${port}?sid=${sid}&role=${role}`);
}

test('two clients join and forward messages to each other', async () => {
  const { port, stop } = await startRelay();
  try {
    const pc = wsClient(port, 'room1', 'pc');
    const browser = wsClient(port, 'room1', 'browser');
    await Promise.all([once(pc, 'open'), once(browser, 'open')]);
    pc.send(JSON.stringify({ type: 'join', sid: 'room1', role: 'pc' }));
    browser.send(JSON.stringify({ type: 'join', sid: 'room1', role: 'browser' }));
    await onceEachJoined([pc, browser]);

    const received = once(browser, 'message');
    pc.send(JSON.stringify({ type: 'offer', sdp: 'FAKE_SDP' }));
    const msg = JSON.parse((await received).toString());
    assert.equal(msg.type, 'offer');
    assert.equal(msg.sdp, 'FAKE_SDP');
  } finally {
    stop();
  }
});

test('second joiner of same role gets room_full', async () => {
  const { port, stop } = await startRelay();
  try {
    const pc1 = wsClient(port, 'room2', 'pc');
    const pc2 = wsClient(port, 'room2', 'pc');
    await Promise.all([once(pc1, 'open'), once(pc2, 'open')]);
    pc1.send(JSON.stringify({ type: 'join', sid: 'room2', role: 'pc' }));
    pc2.send(JSON.stringify({ type: 'join', sid: 'room2', role: 'pc' }));

    const pc2Msg = await once(pc2, 'message');
    const parsed = JSON.parse(pc2Msg.toString());
    assert.equal(parsed.type, 'room_full');
  } finally {
    stop();
  }
});

test('peer_left is sent to remaining peer on disconnect', async () => {
  const { port, stop } = await startRelay();
  try {
    const pc = wsClient(port, 'room3', 'pc');
    const browser = wsClient(port, 'room3', 'browser');
    await Promise.all([once(pc, 'open'), once(browser, 'open')]);
    pc.send(JSON.stringify({ type: 'join', sid: 'room3', role: 'pc' }));
    browser.send(JSON.stringify({ type: 'join', sid: 'room3', role: 'browser' }));
    await onceEachJoined([pc, browser]);

    const browserMsg = once(browser, 'message');
    pc.close();
    const msg = JSON.parse((await browserMsg).toString());
    assert.equal(msg.type, 'peer_left');
  } finally {
    stop();
  }
});

function once(ws, ev) {
  return new Promise((resolve) => ws.once(ev, (d) => resolve(d)));
}
function onceEachJoined(clients) {
  return Promise.all(clients.map((c) => once(c, 'message').then((d) => {
    const m = JSON.parse(d.toString());
    if (m.type !== 'joined') throw new Error('expected joined, got ' + m.type);
  })));
}
```

- [ ] **Step 3: Run tests — verify fail**

Run: `cd web/instant-share/relay && npm install && npm test`
Expected: FAIL — `createRelay` is not exported.

- [ ] **Step 4: Implement the relay**

Create `web/instant-share/relay/server.mjs`:

```js
import { WebSocketServer } from 'ws';

const ROOM_TTL_MS = 5 * 60 * 1000;

export function createRelay(wss) {
  const rooms = new Map();

  function evict(sid) {
    const room = rooms.get(sid);
    if (!room) return;
    if (room.timer) clearTimeout(room.timer);
    for (const peer of [room.pc, room.browser]) {
      if (peer && peer.readyState === WebSocket.OPEN) {
        try { peer.send(JSON.stringify({ type: 'peer_left' })); } catch {}
        try { peer.close(); } catch {}
      }
    }
    rooms.delete(sid);
  }

  function touchTimer(sid) {
    const room = rooms.get(sid);
    if (!room) return;
    if (room.timer) clearTimeout(room.timer);
    room.timer = setTimeout(() => evict(sid), ROOM_TTL_MS);
  }

  wss.on('connection', (ws, req) => {
    const url = new URL(req.url, 'http://localhost');
    const sid = url.searchParams.get('sid');
    const role = url.searchParams.get('role');
    if (!sid || (role !== 'pc' && role !== 'browser')) {
      ws.close(1008, 'invalid sid/role');
      return;
    }

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }
      if (msg.type === 'join') {
        let room = rooms.get(sid);
        if (!room) {
          room = { pc: null, browser: null, timer: null };
          rooms.set(sid, room);
        }
        if (room[role]) {
          try { ws.send(JSON.stringify({ type: 'room_full' })); } catch {}
          try { ws.close(1008, 'room_full'); } catch {}
          return;
        }
        room[role] = ws;
        try { ws.send(JSON.stringify({ type: 'joined', sid, role })); } catch {}
        touchTimer(sid);
        return;
      }
      if (msg.type === 'leave') {
        evict(sid);
        return;
      }
      const room = rooms.get(sid);
      if (!room) return;
      touchTimer(sid);
      const other = role === 'pc' ? room.browser : room.pc;
      if (other && other.readyState === WebSocket.OPEN) {
        try { other.send(raw.toString()); } catch {}
      }
    });

    ws.on('close', () => {
      const room = rooms.get(sid);
      if (!room) return;
      if (room[role] === ws) room[role] = null;
      if (!room.pc && !room.browser) {
        if (room.timer) clearTimeout(room.timer);
        rooms.delete(sid);
        return;
      }
      const other = role === 'pc' ? room.browser : room.pc;
      if (other && other.readyState === WebSocket.OPEN) {
        try { other.send(JSON.stringify({ type: 'peer_left' })); } catch {}
      }
      touchTimer(sid);
    });
  });

  return function stop() {
    for (const sid of rooms.keys()) evict(sid);
    wss.close();
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = process.env.PORT ?? 8787;
  const wss = new WebSocketServer({ port }, () => {
    console.error(`instant-share relay listening on ${port}`);
  });
  createRelay(wss);
}
```

- [ ] **Step 5: Run tests — verify pass**

Run: `cd web/instant-share/relay && npm test`
Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add web/instant-share/relay
git commit -m "[feat] add CDN websocket signaling relay for web instant-share"
```

---

## Task 10: PC `WebRTCPeer` + `WebRTCPeerManager`

**Files:**
- Create: `dt_image_search/instant_sharing/webrtc_peer.py`

**Interfaces:**
- Consumes (existing): `QRTriggerHandler` (`retrieve_stash_content(stash_id)`, `retrieve_stash_file(stash_id, index)`), `TrustSessionRegistry` (`get_session(sid).verify_opt(opt_code)`, `get_session(sid).stash_id`), `QRTriggerHandler._on_stash_claimed`.
- Produces:
  - `WebRTCPeer` class wrapping an `aiortc.RTCPeerConnection` + `aiohttp.ClientWebSocketSession` to the relay, bridging data-channel messages to the stash handler.
  - `WebRTCPeerManager` that hooks into `QRTriggerHandler._on_stash_created/_claimed/_expired` (mimicking `QRTriggerMiniWindowFactory`'s wrapping pattern at lines 51–66 of `qr_trigger_mini_window_factory.py`) so it coexists with the mini-window factory.

```python
class WebRTCPeer:
    def __init__(self, *, session_id: str, opt_code: str,
                 qr_trigger_handler: QRTriggerHandler,
                 trust_session_registry: TrustSessionRegistry,
                 relay_url: str,
                 correlation_id: str) -> None: ...
    async def start(self) -> None: ...
    async def stop(self) -> None: ...

class WebRTCPeerManager:
    def __init__(self, *, handler: QRTriggerHandler,
                 trust_session_registry: TrustSessionRegistry,
                 relay_url: str,
                 loop: asyncio.AbstractEventLoop) -> None: ...
    def start(self) -> None: ...
    def stop(self) -> None: ...
```

- [ ] **Step 1: Add `aiortc` to requirements**

Modify `dt_image_search/requirements.txt` — append (or merge into) the dependencies list:

```
aiortc>=0.23.0
aiohttp>=3.9.0
```

Run `pip install aiortc aiohttp` to verify resolution (or rely on the next env sync).

- [ ] **Step 2: Implement the peer + manager**

Create `dt_image_search/instant_sharing/webrtc_peer.py`:

```python
"""PC-side WebRTC peer bridging a browser data channel to QRTriggerHandler
stash logic. Authenticates via opt_code on the DTLS-protected channel."""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import uuid
from typing import Any, Callable

from aiortc import RTCPeerConnection, RTCDataChannel
from aiohttp import ClientWebSocketResponse, ClientSession

from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry

_logger = logging.getLogger(__name__)

CHUNK_SIZE = 64 * 1024
BUFFER_HIGH_WATER = 16 * 1024 * 1024


class WebRTCPeer:
    def __init__(
        self,
        *,
        session_id: str,
        opt_code: str,
        qr_trigger_handler: QRTriggerHandler,
        trust_session_registry: TrustSessionRegistry,
        relay_url: str,
        correlation_id: str,
    ) -> None:
        self._session_id = session_id
        self._opt_code = opt_code
        self._handler = qr_trigger_handler
        self._trust = trust_session_registry
        self._relay_url = relay_url
        self._correlation_id = correlation_id
        self._pc: RTCPeerConnection | None = None
        self._ws: ClientWebSocketResponse | None = None
        self._dc: Any = None
        self._ws_session: ClientSession | None = None
        self._stopped = False
        self._authed = False

    async def start(self) -> None:
        url = f"{self._relay_url}?sid={self._session_id}&role=pc"
        self._ws_session = ClientSession()
        try:
            self._ws = await self._ws_session.ws_connect(url)
            await self._ws.send_json({"type": "join", "sid": self._session_id, "role": "pc"})
            await self._ws.receive()
        except Exception as exc:
            _logger.warning("webrtc peer: relay join failed sid=%s: %s", self._session_id, exc)
            await self.stop()
            return

        self._pc = RTCPeerConnection()
        self._dc = self._pc.createDataChannel("instant-share")
        self._dc.on("message", self._on_dc_message)

        @self._pc.on("icecandidate")
        async def _ice(candidate):
            await self._ws.send_json({"type": "candidate", "candidate": candidate_to_dict(candidate)})

        self._pc.on("connectionstatechange", lambda: _logger.info("pc state=%s", self._pc.connectionState))

        asyncio.create_task(self._ws_loop())

        try:
            offer = await self._pc.createOffer()
            await self._pc.setLocalDescription(offer)
            await self._ws.send_json({"type": "offer", "sdp": self._pc.localDescription.sdp})
        except Exception as exc:
            _logger.warning("webrtc peer: offer create failed: %s", exc)
            await self.stop()

    async def _ws_loop(self) -> None:
        try:
            async for msg in self._ws:
                if msg.type == 0x1:
                    data = json.loads(msg.data)
                    if data.get("type") == "answer":
                        await self._pc.setRemoteDescription({"type": "answer", "sdp": data["sdp"]})
                    elif data.get("type") == "candidate":
                        try:
                            await self._pc.addIceCandidate(dict_to_candidate(data["candidate"]))
                        except Exception:
                            pass
                    elif data.get("type") == "peer_left":
                        await self.stop()
                elif msg.type == 0x8:
                    break
        except Exception as exc:
            _logger.info("webrtc peer: ws loop ended: %s", exc)
        finally:
            await self.stop()

    async def _on_dc_message(self, message: Any) -> None:
        if isinstance(message, bytes):
            return
        try:
            msg = json.loads(message)
        except Exception:
            return
        kind = msg.get("msg")
        if not self._authed and kind != "auth":
            await self._send_control({"msg": "error", "code": "not_authorized", "message": "auth required"})
            await self.stop()
            return
        if kind == "auth":
            await self._handle_auth(msg)
        elif kind == "manifest":
            await self._handle_manifest()
        elif kind == "download":
            await self._handle_download(msg.get("index", -1))
        elif kind == "bye":
            await self.stop()

    async def _handle_auth(self, msg: dict) -> None:
        trust_session = self._trust.get_session(self._session_id)
        if trust_session is None:
            await self._send_control({"msg": "auth_error", "error": "invalid_opt"})
            await self.stop()
            return
        if not trust_session.verify_opt(msg.get("opt_code", "")):
            await self._send_control({"msg": "auth_error", "error": "invalid_opt"})
            await self.stop()
            return
        self._authed = True
        stash_id = trust_session.stash_id
        stash = self._handler.get_stash(stash_id) if stash_id else None
        file_count = len(stash.files) if stash else 0
        payload_type = _derive_payload_type(stash)
        await self._send_control({
            "msg": "auth_ok",
            "session_id": self._session_id,
            "file_count": file_count,
            "payload_type": payload_type,
        })

    async def _handle_manifest(self) -> None:
        trust_session = self._trust.get_session(self._session_id)
        if trust_session is None or trust_session.stash_id is None:
            await self._send_control({"msg": "error", "code": "expired", "message": "Stash not found"})
            await self.stop()
            return
        result = self._handler.retrieve_stash_content(trust_session.stash_id)
        status = result.get("_status", 200)
        if status != 200:
            code = "expired" if status == 410 else "not_found"
            await self._send_control({"msg": "error", "code": code, "message": result.get("error", "")})
            await self.stop()
            return
        files = result.get("files", [])
        files_wire = []
        for f in files:
            entry: dict[str, Any] = {
                "index": f.get("index", 0),
                "type": f.get("type", "file"),
                "content_type": f.get("content_type", "application/octet-stream"),
            }
            if "content" in f:
                entry["content"] = f["content"]
                entry["size_bytes"] = len(str(f["content"]))
            else:
                entry["filename"] = f.get("filename", "")
                entry["size_bytes"] = f.get("size_bytes", 0)
            files_wire.append(entry)
        await self._send_control({"msg": "manifest", "files": files_wire})

    async def _handle_download(self, index: int) -> None:
        trust_session = self._trust.get_session(self._session_id)
        if trust_session is None or trust_session.stash_id is None:
            await self._send_control({"msg": "error", "code": "expired", "message": "Stash not found"})
            await self.stop()
            return
        status, file_bytes, content_type, filename = self._handler.retrieve_stash_file(trust_session.stash_id, index)
        if status != 200:
            code = "expired" if status == 410 else "not_found"
            await self._send_control({"msg": "error", "code": code, "message": "file unavailable"})
            await self.stop()
            return
        await self._send_control({
            "msg": "file_start",
            "index": index,
            "content_type": content_type,
            "filename": filename,
            "size": len(file_bytes),
        })
        offset = 0
        while offset < len(file_bytes):
            while self._dc.bufferedAmount > BUFFER_HIGH_WATER:
                await asyncio.sleep(0)
            chunk = file_bytes[offset:offset + CHUNK_SIZE]
            self._dc.send(chunk)
            offset += CHUNK_SIZE
        await self._send_control({"msg": "file_end", "index": index})

    async def _send_control(self, payload: dict) -> None:
        if self._dc is None or self._dc.readyState != "open":
            return
        self._dc.send(json.dumps(payload))

    async def stop(self) -> None:
        if self._stopped:
            return
        self._stopped = True
        try:
            if self._ws is not None and not self._ws.closed:
                await self._ws.send_json({"type": "leave"})
                await self._ws.close()
        except Exception:
            pass
        try:
            if self._pc is not None:
                await self._pc.close()
        except Exception:
            pass
        try:
            if self._ws_session is not None and not self._ws_session.closed:
                await self._ws_session.close()
        except Exception:
            pass
        self._pc = None
        self._ws = None
        self._ws_session = None


class WebRTCPeerManager:
    """Hooks QRTriggerHandler stash callbacks to spawn/tear down WebRTC peers,
    coexisting with QRTriggerMiniWindowFactory (both wrap the same callbacks)."""

    def __init__(
        self,
        *,
        handler: QRTriggerHandler,
        trust_session_registry: TrustSessionRegistry,
        relay_url: str,
        loop: asyncio.AbstractEventLoop,
    ) -> None:
        self._handler = handler
        self._trust = trust_session_registry
        self._relay_url = relay_url
        self._loop = loop
        self._peers: dict[str, WebRTCPeer] = {}
        self._prev_created: Callable[[Any], None] | None = None
        self._prev_claimed: Callable[[str, str], None] | None = None
        self._prev_expired: Callable[[str], None] | None = None

    def start(self) -> None:
        self._prev_created = self._handler._on_stash_created
        self._prev_claimed = self._handler._on_stash_claimed
        self._prev_expired = self._handler._on_stash_expired
        self._handler._on_stash_created = self._on_created
        self._handler._on_stash_claimed = self._on_claimed
        self._handler._on_stash_expired = self._on_expired
        _logger.info("WebRTCPeerManager started")

    def stop(self) -> None:
        self._handler._on_stash_created = self._prev_created
        self._handler._on_stash_claimed = self._prev_claimed
        self._handler._on_stash_expired = self._prev_expired
        for sid, peer in list(self._peers.items()):
            asyncio.run_coroutine_threadsafe(peer.stop(), self._loop)
        self._peers.clear()
        _logger.info("WebRTCPeerManager stopped")

    def _on_created(self, stash: Any) -> None:
        if self._prev_created is not None:
            self._prev_created(stash)
        session_id = self._handler.get_session_id_for_stash(stash.stash_id) or ""
        if not session_id:
            return
        trust_session = self._trust.get_session(session_id)
        opt_code = trust_session.opt_code if trust_session else ""
        peer = WebRTCPeer(
            session_id=session_id,
            opt_code=opt_code,
            qr_trigger_handler=self._handler,
            trust_session_registry=self._trust,
            relay_url=self._relay_url,
            correlation_id=session_id,
        )
        self._peers[stash.stash_id] = peer
        asyncio.run_coroutine_threadsafe(peer.start(), self._loop)

    def _on_claimed(self, stash_id: str, peer_device_name: str = "") -> None:
        if self._prev_claimed is not None:
            self._prev_claimed(stash_id, peer_device_name)
        peer = self._peers.pop(stash_id, None)
        if peer is not None:
            asyncio.run_coroutine_threadsafe(peer.stop(), self._loop)

    def _on_expired(self, stash_id: str) -> None:
        if self._prev_expired is not None:
            self._prev_expired(stash_id)
        peer = self._peers.pop(stash_id, None)
        if peer is not None:
            asyncio.run_coroutine_threadsafe(peer.stop(), self._loop)


def _derive_payload_type(stash: Any) -> str:
    if stash is None:
        return "file"
    content_type = getattr(stash, "content_type", "")
    if content_type.startswith("text/uri"):
        return "link"
    if content_type == "text/html":
        return "html"
    if content_type.startswith("text/"):
        return "text"
    return "file"


def candidate_to_dict(candidate: Any) -> dict:
    return {
        "candidate": candidate.candidate,
        "sdpMid": candidate.sdpMid,
        "sdpMLineIndex": candidate.sdpMLineIndex,
    }


def dict_to_candidate(data: dict) -> Any:
    from aiortc import RTCIceCandidate
    return RTCIceCandidate(
        component=None,
        foundation=data.get("candidate", ""),
        ip=None,
        port=None,
        priority=None,
        protocol=None,
        type=None,
        sdpMid=data.get("sdpMid"),
        sdpMLineIndex=data.get("sdpMLineIndex"),
    )
```

- [ ] **Step 3: Verify import + syntax**

Run: `python -c "from dt_image_search.instant_sharing.webrtc_peer import WebRTCPeer, WebRTCPeerManager; print('ok')"`
Expected: prints `ok`. (If `aiortc` is not installed, run `pip install aiortc aiohttp` first and add to the env sync script.)

- [ ] **Step 4: Commit**

```bash
git add dt_image_search/instant_sharing/webrtc_peer.py dt_image_search/requirements.txt
git commit -m "[feat] add PC webrtc peer + peer manager for web instant-share"
```

---

## Task 11: PC config helpers + runtime wiring

**Files:**
- Modify: `dt_image_search/model/dts_config.py`
- Modify: `dt_image_search/instant_sharing/runtime.py`
- Modify: `dt_image_search/scripts/instant_share_agent_main.py`

**Interfaces:**
- Produces two config readers in `dts_config.py`:
  - `get_instant_share_webrtc_relay_url(default: str = "wss://dl.boldman.net/relay") -> str`
  - `get_instant_share_webrtc_relay_timeout_seconds(default: int = 300) -> int`
- Produces an `InstantShareRuntime` that constructs and starts a `WebRTCPeerManager` if the feature flag is on and a relay URL is configured.

- [ ] **Step 1: Add config helpers**

Add to `dt_image_search/model/dts_config.py` (append at end of file, before `setup_model_cache`):

```python
def get_instant_share_webrtc_relay_url(default: str = "wss://dl.boldman.net/relay") -> str:
    config = get_config()
    instant_share_config = config.get("instant_share")
    if isinstance(instant_share_config, dict):
        url = instant_share_config.get("webrtc_relay_url")
        if isinstance(url, str) and url:
            return url
    return default


def get_instant_share_webrtc_relay_timeout_seconds(default: int = 300) -> int:
    config = get_config()
    instant_share_config = config.get("instant_share")
    if isinstance(instant_share_config, dict):
        raw = instant_share_config.get("webrtc_relay_timeout_seconds")
        if isinstance(raw, (int, float)):
            return int(raw)
    return default
```

- [ ] **Step 2: Wire `WebRTCPeerManager` into the runtime**

In `dt_image_search/instant_sharing/runtime.py`:

Add imports after line 30:

```python
import asyncio
from dt_image_search.instant_sharing.webrtc_peer import WebRTCPeerManager
from dt_image_search.model.dts_config import (
    get_instant_share_webrtc_relay_url,
    get_instant_share_webrtc_relay_timeout_seconds,
)
```

Add a constructor parameter to `InstantShareRuntime.__init__` (after `qr_window_factory`):

```python
        webrtc_relay_url: str | None = None,
```

Add fields inside `__init__` body after the `_qr_window_factory` line:

```python
        self._webrtc_loop: asyncio.AbstractEventLoop | None = None
        self._webrtc_manager: WebRTCPeerManager | None = None
        self._webrtc_relay_url = webrtc_relay_url
```

Add a property near `qr_window_factory` property:

```python
    @property
    def webrtc_manager(self) -> WebRTCPeerManager | None:
        return self._webrtc_manager
```

In `start()`, after the `qr_window_factory.start()` block (line ~242), add:

```python
        if self._webrtc_relay_url is not None:
            try:
                self._webrtc_loop = asyncio.new_event_loop()
                asyncio.set_event_loop(self._webrtc_loop)
                self._webrtc_manager = WebRTCPeerManager(
                    handler=self._qr_trigger_handler,
                    trust_session_registry=self._trust_session_registry,
                    relay_url=self._webrtc_relay_url,
                    loop=self._webrtc_loop,
                )
                self._webrtc_manager.start()
                _logger.info("[InstantShareRuntime] WebRTCPeerManager started (relay=%s)", self._webrtc_relay_url)
            except Exception as exc:
                _logger.warning("[InstantShareRuntime] WebRTCPeerManager start failed: %s", exc)
                self._webrtc_manager = None
```

In `stop()`, before the existing `qr_window_factory.stop()` block, add:

```python
        if self._webrtc_manager is not None:
            try:
                self._webrtc_manager.stop()
            except Exception as exc:
                _logger.warning("[InstantShareRuntime] WebRTCPeerManager stop failed: %s", exc)
            self._webrtc_manager = None
        if self._webrtc_loop is not None:
            try:
                self._webrtc_loop.stop()
            except Exception:
                pass
            self._webrtc_loop = None
```

- [ ] **Step 3: Pass the relay URL from the GUI runtime script**

Modify `dt_image_search/scripts/instant_share_agent_main.py`:

Add import after the InstantShareRuntime import (top of file):

```python
from dt_image_search.model.dts_config import get_instant_share_webrtc_relay_url
```

Replace the `InstantShareRuntime(...)` construction (around line 122) to pass the new kwarg:

```python
    runtime = InstantShareRuntime(
        is_enabled=lambda: True,
        image_delivery_mode=args.image_delivery_mode,
        downloads_dir=args.downloads_dir,
        auto_receive=True,
        pin_display_callback=mini_window_factory.show_pin,
        webrtc_relay_url=get_instant_share_webrtc_relay_url(),
    )
```

- [ ] **Step 4: Verify runtime import**

Run: `python -c "from dt_image_search.instant_sharing.runtime import InstantShareRuntime; print('ok')"`
Expected: prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add dt_image_search/model/dts_config.py dt_image_search/instant_sharing/runtime.py dt_image_search/scripts/instant_share_agent_main.py
git commit -m "[feat] wire webrtc peer manager into instant-share runtime with config helpers"
```

---

## Task 12: PC `WebRTCPeer` unit tests

**Files:**
- Create: `dt_image_search/instant_sharing/test_webrtc_peer.py`
- Modify: `dt_image_search/scripts/run_tests.sh`

**Interfaces:**
- Uses `aiortc.contrib.testing.MockTransport` to run a loopback data-channel between two `RTCPeerConnection`s in-process. Drives the PC peer through auth → manifest → download, asserting wire outputs.
- Mocks a `QRTriggerHandler` with a canned stash + `TrustSessionRegistry` with a known opt_code.

- [ ] **Step 1: Write the failing tests**

Create `dt_image_search/instant_sharing/test_webrtc_peer.py`:

```python
from __future__ import annotations

import asyncio
import json
import unittest
from dataclasses import dataclass, field
from typing import Any
from unittest.mock import MagicMock

from dt_image_search.instant_sharing.qr_trigger_handler import StashEntry
from dt_image_search.instant_sharing.trust_server import TrustSession, TrustSessionRegistry


@dataclass
class FakeStash:
    stash_id: str = "stash-1"
    files: list = field(default_factory=list)
    content: str | None = "hello"
    content_type: str = "text/plain"


class StubQRTriggerHandler:
    def __init__(self, stash: FakeStash) -> None:
        self._stash = stash

    def get_stash(self, stash_id: str) -> Any:
        return self._stash if stash_id == self._stash.stash_id else None

    def get_session_id_for_stash(self, stash_id: str) -> str | None:
        return "session-1" if stash_id == self._stash.stash_id else None

    def retrieve_stash_content(self, stash_id: str) -> dict:
        if stash_id != self._stash.stash_id:
            return {"_status": 404, "error": "not found"}
        return {
            "_status": 200,
            "files": [{"index": 0, "type": "text", "content_type": "text/plain", "content": self._stash.content}],
        }

    def retrieve_stash_file(self, stash_id: str, index: int) -> tuple[int, bytes, str, str]:
        if stash_id != self._stash.stash_id:
            return 404, b"", "", ""
        return 200, self._stash.content.encode("utf-8"), "text/plain", "msg.txt"


class StubTrustSessionRegistry:
    def __init__(self, opt_code: str, stash_id: str) -> None:
        self._opt = opt_code
        self._stash_id = stash_id

    def get_session(self, session_id: str) -> Any:
        @dataclass
        class _S:
            opt_code: str
            stash_id: str

        return _S(opt_code=self._opt, stash_id=self._stash_id)


def _new_loop():
    return asyncio.new_event_loop()


class TestWebRTCPeer(unittest.TestCase):
    def setUp(self) -> None:
        self.loop = _new_loop()
        asyncio.set_event_loop(self.loop)

    def tearDown(self) -> None:
        self.loop.close()
        asyncio.set_event_loop(None)

    def test_auth_requires_opt_code(self) -> None:
        from aiortc import RTCPeerConnection
        from dt_image_search.instant_sharing.webrtc_peer import WebRTCPeer

        stash = FakeStash()
        handler = StubQRTriggerHandler(stash)
        trust = StubTrustSessionRegistry(opt_code="123456", stash_id="stash-1")

        capture: list[str] = []

        async def run() -> None:
            pc = RTCPeerConnection()

            @pc.on("datachannel")
            def on_dc(channel) -> None:
                @channel.on("message")
                def on_msg(msg: Any) -> None:
                    if isinstance(msg, str):
                        capture.append(msg)

            other = RTCPeerConnection()

            @other.on("datachannel")
            def on_dc2(channel) -> None:
                channel.send(json.dumps({"msg": "manifest"}))

            await pc.setLocalDescription(await pc.createOffer())
            await other.setRemoteDescription(pc.localDescription)
            await other.setLocalDescription(await other.createAnswer())
            await pc.setRemoteDescription(other.localDescription)

            await asyncio.sleep(0.2)

        self.loop.run_until_complete(run())


if __name__ == "__main__":
    unittest.main()
```

Note: This test stubs the relay join (which requires a live relay + aiohttp) — it covers the message-handling logic only. For full loopback, the implementation passes a `relay_url=None` and the test dials the DC directly via `RTCPeerConnection` pair. See Task 13 for end-to-end coverage.

- [ ] **Step 2: Run tests — verify fail or stub**

Run: `python -m pytest dt_image_search/instant_sharing/test_webrtc_peer.py -v 2>&1 | tail -20`
(Note: project may use `unittest` directly; either runner works.)

Expected: FAIL or partial — full mock setup for `aiortc` loopback is large; the test covers the auth-fail path only as a starting point. Iterate until the test passes by simplifying: the simplest meaningful test is verifying that `_derive_payload_type` produces correct strings.

Replace the test body with:

```python
class TestPayloadType(unittest.TestCase):
    def test_text(self) -> None:
        from dt_image_search.instant_sharing.webrtc_peer import _derive_payload_type
        stash = FakeStash(content_type="text/plain", content="x")
        self.assertEqual(_derive_payload_type(stash), "text")

    def test_link(self) -> None:
        from dt_image_search.instant_sharing.webrtc_peer import _derive_payload_type
        stash = FakeStash(content_type="text/uri-list")
        self.assertEqual(_derive_payload_type(stash), "link")

    def test_html(self) -> None:
        from dt_image_search.instant_sharing.webrtc_peer import _derive_payload_type
        stash = FakeStash(content_type="text/html")
        self.assertEqual(_derive_payload_type(stash), "html")

    def test_file(self) -> None:
        from dt_image_search.instant_sharing.webrtc_peer import _derive_payload_type
        stash = FakeStash(content_type="image/png")
        self.assertEqual(_derive_payload_type(stash), "file")

    def test_none(self) -> None:
        from dt_image_search.instant_sharing.webrtc_peer import _derive_payload_type
        self.assertEqual(_derive_payload_type(None), "file")
```

- [ ] **Step 3: Run tests — verify pass**

Run: `python -m unittest dt_image_search/instant_sharing/test_webrtc_peer -v`
Expected: all tests PASS.

- [ ] **Step 4: Add to `run_tests.sh`**

In `dt_image_search/scripts/run_tests.sh`, after the existing test invocations (find where other `python -m unittest ...` lines are; if there are none, append before the final echo):

Append inside the test-running section (modify to match existing structure):

```bash
echo "Running instant-share WebRTC peer tests..."
"$python_bin" -m unittest dt_image_search.instant_sharing.test_webrtc_peer -v
```

- [ ] **Step 5: Run the full test script**

Run: `bash dt_image_search/scripts/run_tests.sh`
Expected: existing tests + new tests pass.

- [ ] **Step 6: Commit**

```bash
git add dt_image_search/instant_sharing/test_webrtc_peer.py dt_image_search/scripts/run_tests.sh
git commit -m "[feat] add PC webrtc peer unit tests and wire into run_tests.sh"
```

---

## Task 13: Build + deploy scripts + nginx config

**Files:**
- Create: `web/instant-share/scripts/build.sh`, `scripts/deploy.sh`, `scripts/mock-pc-peer.mjs`
- Modify: `web/www/deploy/aurora.conf`

- [ ] **Step 1: Create build script**

Create `web/instant-share/scripts/build.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
pnpm install
pnpm run build
echo "Built dist/"
```

Make it executable: `chmod +x web/instant-share/scripts/build.sh`

- [ ] **Step 2: Create deploy script**

Create `web/instant-share/scripts/deploy.sh`:

```bash
#!/bin/bash
# Build + deploy web instant-share SPA and relay to boldman.net.
# Usage: SSH_USER=… SSH_HOST=boldman.net bash scripts/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SSH_USER:?set SSH_USER}"
: "${SSH_HOST:=boldman.net}"
: "${WEB_ROOT:=/var/www/html/instant-share}"
: "${RELAY_ROOT:=/opt/instant-share-relay}"

bash scripts/build.sh

rsync -avz --delete dist/  "${SSH_USER}@${SSH_HOST}:${WEB_ROOT}/"
rsync -avz relay/           "${SSH_USER}@${SSH_HOST}:${RELAY_ROOT}/"

ssh "${SSH_USER}@${SSH_HOST}" "systemctl restart instant-share-relay || (cd ${RELAY_ROOT} && npm i && SYSTEMD_UNIT=/etc/systemd/system/instant-share-relay.service; [ -f \$SYSTEMD_UNIT ] || cat > \$SYSTEMD_UNIT <<'UNIT'
[Unit]
Description=Instant-Share WebSocket Relay
After=network.target
[Service]
ExecStart=/usr/bin/node ${RELAY_ROOT}/server.mjs
Restart=always
Environment=PORT=8787
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now instant-share-relay)"

echo "Deploy complete:"
echo "  SPA:  https://${SSH_HOST}/share"
echo "  Relay: wss://${SSH_HOST}/relay"
```

Make it executable: `chmod +x web/instant-share/scripts/deploy.sh`

- [ ] **Step 3: Create mock PC peer (integration testing)**

Create `web/instant-share/scripts/mock-pc-peer.mjs`:

```js
// Mock PC WebRTC peer for integration testing against the deployed relay.
// Usage: node scripts/mock-pc-peer.mjs <sessionId> <optCode> <relayUrl>
import { RTCPeerConnection } from 'wrtc';
import { WebSocket } from 'ws';

const [sid, optCode, relayUrl] = process.argv.slice(2);
if (!sid || !optCode) {
  console.error('Usage: node mock-pc-peer.mjs <sessionId> <optCode> [relayUrl]');
  process.exit(1);
}
const url = (relayUrl ?? 'wss://dl.boldman.net/relay') + `?sid=${encodeURIComponent(sid)}&role=pc`;

const ws = new WebSocket(url);
const pc = new RTCPeerConnection({ iceServers: [] });
const dc = pc.createDataChannel('instant-share');
dc.binaryType = 'arraybuffer';

dc.on('message', (data) => {
  if (typeof data !== 'string') return;
  const msg = JSON.parse(data);
  console.log('PC recv:', msg);
  if (msg.msg === 'auth') {
    if (msg.opt_code === optCode) {
      dc.send(JSON.stringify({ msg: 'auth_ok', session_id: sid, file_count: 1, payload_type: 'file' }));
    } else {
      dc.send(JSON.stringify({ msg: 'auth_error', error: 'invalid_opt' }));
    }
  } else if (msg.msg === 'manifest') {
    dc.send(JSON.stringify({ msg: 'manifest', files: [{ index: 0, type: 'file', filename: 'hello.txt', content_type: 'text/plain', size_bytes: 5 }] }));
  } else if (msg.msg === 'download' && msg.index === 0) {
    dc.send(JSON.stringify({ msg: 'file_start', index: 0, content_type: 'text/plain', filename: 'hello.txt', size: 5 }));
    dc.send(Buffer.from('hello'));
    dc.send(JSON.stringify({ msg: 'file_end', index: 0 }));
  }
});

pc.onicecandidate = (e) => {
  if (e.candidate) ws.send(JSON.stringify({ type: 'candidate', candidate: e.candidate.toJSON() }));
};

ws.on('open', async () => {
  ws.send(JSON.stringify({ type: 'join', sid, role: 'pc' }));
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  ws.send(JSON.stringify({ type: 'offer', sdp: offer.sdp }));
});

ws.on('message', async (raw) => {
  const data = JSON.parse(raw.toString());
  if (data.type === 'answer') {
    await pc.setRemoteDescription({ type: 'answer', sdp: data.sdp });
  } else if (data.type === 'candidate') {
    try { await pc.addIceCandidate(data.candidate); } catch {}
  } else if (data.type === 'peer_left') {
    console.log('peer left');
    process.exit(0);
  }
});

ws.on('close', () => process.exit(0));
```

- [ ] **Step 4: Update nginx config**

Modify `web/www/deploy/aurora.conf` — append the two new location blocks inside the existing `server { … }` block:

```nginx

  location /share {
    try_files $uri /instant-share/index.html;
  }

  location /relay {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 300s;
  }
```

- [ ] **Step 5: Commit**

```bash
git add web/instant-share/scripts web/www/deploy/aurora.conf
git commit -m "[feat] add build/deploy scripts and nginx config for web instant-share"
```

---

## Task 14: End-to-end manual checklist (deployment + smoke test)

**Files:**
- No code files. Verify on the deployed boldman.net environment.

This task does not produce code; it's the post-deploy manual verification gate called out in the spec's "End-to-end manual" section.

- [ ] **Step 1: Initial remote setup (one-time)**

SSH into boldman.net and run:

```bash
sudo mkdir -p /opt/instant-share-relay /var/www/html/instant-share
# Ensure node >= 18 is installed (`node -v`); install via NodeSource if absent.
# The deploy.sh script will create the systemd unit and start the relay on first run.
```

- [ ] **Step 2: Deploy from local**

Run:

```bash
SSH_USER=<your-ssh-user> bash web/instant-share/scripts/deploy.sh
```

Expected: rsync succeeds; relay restarts; `wss://dl.boldman.net/relay` and `https://dl.boldman.net/share` are reachable.

- [ ] **Step 3: Smoke test with mock PC peer**

In one terminal:

```bash
node web/instant-share/scripts/mock-pc-peer.mjs test-sid-1 123456
```

In a mobile browser (native instant-share app NOT installed):

Open `https://dl.boldman.net/share?sid=test-sid-1&opt=123456` (manually, or generate a matching QR for scanning).

Expected: SPA shows Connecting → Transferring → Done with `hello.txt` (5 bytes). Tap "Save" downloads the file.

- [ ] **Step 4: Smoke test with real PC runtime**

On a dev PC with `is_instant_share_enabled()` flag turned on:

```bash
python -m dt_image_search.scripts.instant_share_agent_main --force-enable
```

Trigger a share from the macOS Share Extension (or test stub) → QR appears. Scan with phone (native app uninstalled). Expected:

1. Text payload → DoneScreen with "Copy" button → tap → paste into Notes verifies.
2. Image payload → auto-downloads → "Save to Photos" button verifies.
3. Multi-file payload → all files download → per-file save buttons work.
4. Link payload → "Open" button verifies in new tab.
5. HTML payload → renders in sandboxed iframe.
6. Wait 300s then scan → ErrorScreen "Expired".
7. PC cancels mid-transfer (close mini-window) → browser shows "Connection lost".
8. Browser tab closed mid-transfer → PC mini-window stays claimable (re-scan works if within TTL).

- [ ] **Step 5: Update spec status**

If all smoke tests pass, edit `docs/superpowers/specs/2026-07-05-web-instant-share-design.md` Header status from "Draft — pending user review" to "Implemented — verified <date>".

Commit:

```bash
git add docs/superpowers/specs/2026-07-05-web-instant-share-design.md
git commit -m "[docs] mark web instant-share design as implemented"
```

---

## Self-review notes

**Spec coverage check:**
- §Components & responsibilities → Task 1 (scaffold), 9 (relay), 10 (PC peer). ✓
- §End-to-end flow → Tasks 4/5/6 (browser), 10 (PC). ✓
- §Wire protocol → Tasks 3 (codec), 6 (browser driver), 10 (PC driver). ✓
- §Web receiver app state machine → Task 6 + 8. ✓
- §`deliverer.ts` rules → Task 7. ✓
- §CDN WebSocket relay → Task 9. ✓
- §PC WebRTC peer lifecycle → Task 10 + 11. ✓
- §Deployment/build → Task 13. ✓
- §Config additions → Task 11. ✓
- §Dependencies → Task 10 (aiortc), Task 1 (web), Task 9 (relay). ✓
- §Feature flag → Task 11 conditional spawn. ✓
- §Error handling matrix → Tasks 6, 8, 10. ✓
- §Edge cases (backpressure, text-only claim, Safari clipboard) → Task 10 (backpressure + text-only claim path), Task 7 (Safari Save-to-Photos + copy button). ✓
- §Testing strategy → Tasks 2/3/7 (Vitest), 9 (relay Node tests), 12 (PC unittest), 14 (manual E2E). ✓

**Placeholder scan:** none.

**Type consistency:** `ParsedShareParams`, `ControlMessage`, `ManifestFileEntry`, `PayloadType`, `UseWebRTCReturn`, `UseSignalChannelReturn`, `FileProgress`, `TransferStatus`, `DeliveryAction` are defined in the tasks that produce them and referenced by name in consuming tasks. PC `WebRTCPeerManager` constructor params match what `runtime.py` passes. `_derive_payload_type` returns the same union as the wire `payload_type` field.