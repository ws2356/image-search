# Web Instant Share — IndexedDB Session Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist received instant-share sessions and files in IndexedDB so that reloading the SPA loads cached content without reconnecting.

**Architecture:** A new `cache.ts` service module wraps IndexedDB with async CRUD functions. `useTransfer` fires cache writes on each completed file. `App.tsx` checks cache on load — if a `complete` session is found, it skips signaling/WebRTC entirely and reconstructs the UI state from cache.

**Tech Stack:** React 18, TypeScript, Vite, Vitest + jsdom, IndexedDB (browser native), `fake-indexeddb` (dev dep for tests)

## Global Constraints

- Database name: `instant-share-cache`, version 1
- Two object stores: `sessions` (keyPath: `sessionId`), `files` (auto-increment, index on `sessionId`)
- Session TTL: 7 days from `completedAt`
- All content types stored as Blob (text/link/html encoded to UTF-8, binary as-is)
- Cache check runs before signaling/WebRTC/transfer hooks are initialized
- Cache writes are fire-and-forget (never block the transfer protocol)
- IndexedDB errors never surface to the user; transfer proceeds without caching
- No new production npm dependencies

---

### Task 1: Install fake-indexeddb dev dependency and configure test setup

**Files:**
- Modify: `web/instant-share/package.json`
- Modify: `web/instant-share/src/test/setup.ts`

**Interfaces:**
- Produces: Global `indexedDB` available in jsdom test environment

- [ ] **Step 1: Install fake-indexeddb**

Run:
```bash
pnpm add -D fake-indexeddb
```

Expected: `fake-indexeddb` added to `devDependencies` in `package.json` and installed in `node_modules`.

- [ ] **Step 2: Wire fake-indexeddb into test setup**

Read `src/test/setup.ts`:
```typescript
import '@testing-library/jest-dom';
```

Replace with:
```typescript
import '@testing-library/jest-dom';
import 'fake-indexeddb/auto';
```

`fake-indexeddb/auto` monkey-patches `globalThis.indexedDB` and `IDBKeyRange`, so all IndexedDB APIs work transparently in jsdom.

- [ ] **Step 3: Verify IDB is available in test context**

Run:
```bash
pnpm test -- --run --reporter=verbose 2>&1 | tail -5
```

Expected: Tests pass (same as before — no new tests yet, just verifying the IDB polyfill doesn't break existing tests).

- [ ] **Step 4: Commit**

```bash
git add web/instant-share/package.json web/instant-share/pnpm-lock.yaml web/instant-share/src/test/setup.ts
git commit -m "test: add fake-indexeddb for IndexedDB test support"
```

---

### Task 2: Create cache service module

**Files:**
- Create: `web/instant-share/src/services/cache.ts`

**Interfaces:**
- Produces:
  ```typescript
  export interface FileEntryInput {
    index: number;
    type: 'text' | 'link' | 'html' | 'file';
    contentType: string;
    filename: string;
    size: number;
    blob: Blob;
  }
  export interface CachedSession {
    session: SessionRecord;
    files: FileRecord[];
  }
  export function openDB(): Promise<IDBDatabase>;
  export function saveFile(sessionId: string, entry: FileEntryInput): Promise<void>;
  export function completeSession(sessionId: string): Promise<void>;
  export function getCachedSession(sessionId: string): Promise<CachedSession | null>;
  export function cleanExpired(db?: IDBDatabase): Promise<void>;
  ```

- [ ] **Step 1: Write the cache service module**

Create `src/services/cache.ts`:

```typescript
import { log } from '../lib/log';

const DB_NAME = 'instant-share-cache';
const DB_VERSION = 1;
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

interface SessionRecord {
  sessionId: string;
  status: 'transferring' | 'complete';
  completedAt: number | null;
}

interface FileRecord {
  id?: number;
  sessionId: string;
  index: number;
  type: 'text' | 'link' | 'html' | 'file';
  contentType: string;
  filename: string;
  size: number;
  blob: Blob;
}

export interface FileEntryInput {
  index: number;
  type: 'text' | 'link' | 'html' | 'file';
  contentType: string;
  filename: string;
  size: number;
  blob: Blob;
}

export interface CachedSession {
  session: SessionRecord;
  files: FileRecord[];
}

let dbPromise: Promise<IDBDatabase> | null = null;

function promisifyRequest<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function promisifyTransaction(tx: IDBTransaction): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export function openDB(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains('sessions')) {
        db.createObjectStore('sessions', { keyPath: 'sessionId' });
      }
      if (!db.objectStoreNames.contains('files')) {
        const fileStore = db.createObjectStore('files', { autoIncrement: true });
        fileStore.createIndex('sessionId', 'sessionId', { unique: false });
      }
    };
    request.onsuccess = () => {
      const db = request.result;
      cleanExpired(db)
        .catch((err) => log.warn('cache: cleanExpired on open failed', err))
        .finally(() => resolve(db));
    };
    request.onerror = () => {
      log.warn('cache: openDB failed', request.error);
      reject(request.error);
    };
  });
  return dbPromise;
}

export async function saveFile(sessionId: string, entry: FileEntryInput): Promise<void> {
  try {
    const db = await openDB();
    const tx = db.transaction(['sessions', 'files'], 'readwrite');
    const sessionStore = tx.objectStore('sessions');
    const fileStore = tx.objectStore('files');

    const existing = await promisifyRequest(sessionStore.get(sessionId));
    if (!existing) {
      sessionStore.put({ sessionId, status: 'transferring', completedAt: null });
    }

    fileStore.put({
      sessionId,
      index: entry.index,
      type: entry.type,
      contentType: entry.contentType,
      filename: entry.filename,
      size: entry.size,
      blob: entry.blob,
    });

    await promisifyTransaction(tx);
  } catch (err) {
    log.warn('cache: saveFile failed', err);
  }
}

export async function completeSession(sessionId: string): Promise<void> {
  try {
    const db = await openDB();
    const tx = db.transaction('sessions', 'readwrite');
    const store = tx.objectStore('sessions');
    store.put({ sessionId, status: 'complete', completedAt: Date.now() });
    await promisifyTransaction(tx);
  } catch (err) {
    log.warn('cache: completeSession failed', err);
  }
}

export async function getCachedSession(sessionId: string): Promise<CachedSession | null> {
  try {
    const db = await openDB();
    const session = await promisifyRequest<SessionRecord>(
      db.transaction('sessions').objectStore('sessions').get(sessionId),
    );
    if (!session) return null;

    if (session.status === 'complete' && session.completedAt != null) {
      const age = Date.now() - session.completedAt;
      if (age > SEVEN_DAYS_MS) {
        return null;
      }
    }

    const fileStore = db.transaction('files').objectStore('files');
    const index = fileStore.index('sessionId');
    const files = await promisifyRequest<FileRecord[]>(index.getAll(sessionId));
    files.sort((a, b) => a.index - b.index);

    return { session, files };
  } catch (err) {
    log.warn('cache: getCachedSession failed', err);
    return null;
  }
}

export async function cleanExpired(db?: IDBDatabase): Promise<void> {
  const database = db ?? (await openDB());
  try {
    const tx = database.transaction(['sessions', 'files'], 'readwrite');
    const sessionStore = tx.objectStore('sessions');
    const allSessions = await promisifyRequest<SessionRecord[]>(sessionStore.getAll());

    const now = Date.now();
    const expiredIds: string[] = [];
    for (const s of allSessions) {
      if (s.completedAt != null && now - s.completedAt > SEVEN_DAYS_MS) {
        expiredIds.push(s.sessionId);
        sessionStore.delete(s.sessionId);
      }
    }
    await promisifyTransaction(tx);

    for (const id of expiredIds) {
      const tx2 = database.transaction('files', 'readwrite');
      const store2 = tx2.objectStore('files');
      const idx2 = store2.index('sessionId');
      const keys = await promisifyRequest<IDBValidKey[]>(idx2.getAllKeys(id));
      for (const key of keys) {
        store2.delete(key);
      }
      await promisifyTransaction(tx2);
    }
  } catch (err) {
    log.warn('cache: cleanExpired failed', err);
  }
}
```

- [ ] **Step 2: Verify the module compiles**

Run:
```bash
pnpm exec tsc --noEmit 2>&1
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add web/instant-share/src/services/cache.ts
git commit -m "feat: add IndexedDB cache service for instant-share sessions"
```

---

### Task 3: Write tests for cache service

**Files:**
- Create: `web/instant-share/src/services/cache.test.ts`

**Interfaces:**
- Consumes: `cache.ts` — all exported functions and types
- Produces: passing test suite

- [ ] **Step 1: Write the test file**

Create `src/services/cache.test.ts`:

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { openDB, saveFile, completeSession, getCachedSession, cleanExpired } from './cache';
import type { FileEntryInput, CachedSession } from './cache';

function makeFileEntry(over?: Partial<FileEntryInput>): FileEntryInput {
  return {
    index: 0,
    type: 'file',
    contentType: 'image/png',
    filename: 'photo.png',
    size: 3,
    blob: new Blob([new Uint8Array([1, 2, 3])], { type: 'image/png' }),
    ...over,
  };
}

function makeTextEntry(over?: Partial<FileEntryInput>): FileEntryInput {
  return {
    index: 0,
    type: 'text',
    contentType: 'text/plain',
    filename: 'text.txt',
    size: 5,
    blob: new Blob(['hello'], { type: 'text/plain' }),
    ...over,
  };
}

beforeEach(async () => {
  const req = indexedDB.deleteDatabase('instant-share-cache');
  await new Promise<void>((resolve, reject) => {
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error);
  });
});

describe('openDB', () => {
  it('opens the database and creates stores', async () => {
    const db = await openDB();
    const names = Array.from(db.objectStoreNames);
    expect(names).toContain('sessions');
    expect(names).toContain('files');
    db.close();
  });

  it('reuses the same connection on subsequent calls', async () => {
    const db1 = await openDB();
    const db2 = await openDB();
    expect(db1).toBe(db2);
    db1.close();
  });
});

describe('saveFile', () => {
  it('creates session row and saves file', async () => {
    await saveFile('sid-1', makeFileEntry());
    const result = await getCachedSession('sid-1');
    expect(result).not.toBeNull();
    expect(result!.session.status).toBe('transferring');
    expect(result!.files).toHaveLength(1);
    expect(result!.files[0].index).toBe(0);
  });

  it('saves multiple files for the same session', async () => {
    await saveFile('sid-1', makeFileEntry({ index: 0 }));
    await saveFile('sid-1', makeFileEntry({ index: 1, filename: 'photo2.png' }));
    const result = await getCachedSession('sid-1');
    expect(result).not.toBeNull();
    expect(result!.files).toHaveLength(2);
    expect(result!.files[0].index).toBe(0);
    expect(result!.files[1].index).toBe(1);
  });
});

describe('completeSession', () => {
  it('updates session status to complete with completedAt', async () => {
    await saveFile('sid-1', makeFileEntry());
    await completeSession('sid-1');
    const result = await getCachedSession('sid-1');
    expect(result).not.toBeNull();
    expect(result!.session.status).toBe('complete');
    expect(result!.session.completedAt).toBeGreaterThan(0);
  });
});

describe('getCachedSession', () => {
  it('returns null for unknown sessionId', async () => {
    const result = await getCachedSession('nonexistent');
    expect(result).toBeNull();
  });

  it('returns transferring session raw (caller decides behavior)', async () => {
    await saveFile('sid-1', makeFileEntry());
    const result = await getCachedSession('sid-1');
    expect(result).not.toBeNull();
    expect(result!.session.status).toBe('transferring');
  });

  it('returns files sorted by index', async () => {
    await saveFile('sid-1', makeFileEntry({ index: 2, filename: 'c.png' }));
    await saveFile('sid-1', makeFileEntry({ index: 0, filename: 'a.png' }));
    await saveFile('sid-1', makeFileEntry({ index: 1, filename: 'b.png' }));
    const result = await getCachedSession('sid-1');
    expect(result!.files.map(f => f.index)).toEqual([0, 1, 2]);
  });

  it('returns null for expired complete session', async () => {
    await saveFile('sid-1', makeFileEntry());
    await completeSession('sid-1');

    const db = await openDB();
    const tx = db.transaction('sessions', 'readwrite');
    const store = tx.objectStore('sessions');
    const past = Date.now() - 8 * 24 * 60 * 60 * 1000;
    store.put({ sessionId: 'sid-1', status: 'complete', completedAt: past });
    await new Promise<void>((resolve) => { tx.oncomplete = () => resolve(); });
    db.close();

    const result = await getCachedSession('sid-1');
    expect(result).toBeNull();
  });
});

describe('cleanExpired', () => {
  it('removes expired complete sessions and their files', async () => {
    await saveFile('sid-1', makeFileEntry());
    await completeSession('sid-1');

    const db = await openDB();
    const tx = db.transaction('sessions', 'readwrite');
    const store = tx.objectStore('sessions');
    const past = Date.now() - 8 * 24 * 60 * 60 * 1000;
    store.put({ sessionId: 'sid-1', status: 'complete', completedAt: past });
    await new Promise<void>((resolve) => { tx.oncomplete = () => resolve(); });
    db.close();

    await cleanExpired();
    const result = await getCachedSession('sid-1');
    expect(result).toBeNull();
  });

  it('keeps non-expired sessions', async () => {
    await saveFile('sid-1', makeFileEntry());
    await completeSession('sid-1');
    await cleanExpired();
    const result = await getCachedSession('sid-1');
    expect(result).not.toBeNull();
  });

  it('keeps transferring sessions regardless of completedAt', async () => {
    await saveFile('sid-1', makeFileEntry());
    await cleanExpired();
    const result = await getCachedSession('sid-1');
    expect(result).not.toBeNull();
  });
});
```

- [ ] **Step 2: Run tests and verify they pass**

Run:
```bash
cd web/instant-share && pnpm test -- --run 2>&1
```

Expected: All tests pass. No failures.

- [ ] **Step 3: Commit**

```bash
git add web/instant-share/src/services/cache.test.ts
git commit -m "test: add unit tests for IndexedDB cache service"
```

---

### Task 4: Integrate cache writes into useTransfer hook

**Files:**
- Modify: `web/instant-share/src/hooks/useTransfer.ts`

**Interfaces:**
- Consumes: `saveFile`, `completeSession` from `../services/cache`
- Consumes: `params.sessionId` (already available in hook scope)
- Produces: (unchanged return type) — callers see no difference

- [ ] **Step 1: Add import**

In `src/hooks/useTransfer.ts`, add at the top alongside existing imports:

```typescript
import { saveFile, completeSession } from '../services/cache';
```

- [ ] **Step 2: Save inline content (text/link/html) in the manifest handler**

In the `handleMessage` callback, locate the `m.msg === 'manifest'` block (around line 129). After the existing lines:

```typescript
pendingManifestRef.current = resp.files;
```

Insert:

```typescript
for (const entry of resp.files) {
  if (entry.content != null && (entry.type === 'text' || entry.type === 'link' || entry.type === 'html')) {
    const mimeType = entry.type === 'html' ? 'text/html' : 'text/plain';
    const blob = new Blob([entry.content], { type: mimeType });
    saveFile(params.sessionId, {
      index: entry.index,
      type: entry.type,
      contentType: mimeType,
      filename: entry.filename ?? `${entry.type}.txt`,
      size: blob.size,
      blob,
    });
  }
}
```

- [ ] **Step 3: Save binary files on file_end**

In the `handleMessage` callback, locate the `m.msg === 'file_end'` block (around line 158). Inside the `if (cur && cur.index === m.index)` branch, after the existing `blob` creation:

```typescript
const blob = new Blob(cur.chunks, { type: cur.contentType });
```

Add:

```typescript
saveFile(params.sessionId, {
  index: m.index,
  type: 'file',
  contentType: cur.contentType,
  filename: cur.filename,
  size: blob.size,
  blob,
});
```

- [ ] **Step 4: Complete session when all downloads finish**

In the `downloadNext` callback, locate the block where all downloads are complete (around line 73):

```typescript
if (idx >= pending.length) {
  log.info('useTransfer: all downloads complete, sending bye');
  transferCompleteRef.current = true;
  sendControl({ msg: 'bye' });
  setState({ type: 'done' });
  webrtc.close();
  return;
}
```

Insert `completeSession` before `sendControl`:

```typescript
if (idx >= pending.length) {
  log.info('useTransfer: all downloads complete, sending bye');
  transferCompleteRef.current = true;
  completeSession(params.sessionId);
  sendControl({ msg: 'bye' });
  setState({ type: 'done' });
  webrtc.close();
  return;
}
```

- [ ] **Step 5: Verify compilation**

Run:
```bash
cd web/instant-share && pnpm exec tsc --noEmit 2>&1
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add web/instant-share/src/hooks/useTransfer.ts
git commit -m "feat: integrate cache writes into useTransfer hook"
```

---

### Task 5: Integrate cache reads into App component

**Files:**
- Modify: `web/instant-share/src/App.tsx`

**Interfaces:**
- Consumes: `getCachedSession` from `../services/cache`
- Produces: (unchanged export) — `export default function App()`

- [ ] **Step 1: Add imports**

In `src/App.tsx`, add:

```typescript
import { useEffect, useState } from 'react';
import { getCachedSession } from './services/cache';
```

- [ ] **Step 2: Move the online-flow hooks into a sub-component and add cache check**

Replace the entire file content with:

```typescript
import { useState, useEffect } from 'react';
import { parseShareUrlParams } from './lib/urlParams';
import { useSignalChannel } from './hooks/useSignalChannel';
import { useWebRTC } from './hooks/useWebRTC';
import { useTransfer, type FileProgress, type TransferState } from './hooks/useTransfer';
import { ConnectingScreen } from './components/ConnectingScreen';
import { ReceiveScreen } from './components/ReceiveScreen';
import { ErrorScreen } from './components/ErrorScreen';
import { log } from './lib/log';
import { getCachedSession } from './services/cache';
import type { ManifestFileEntry } from './lib/protocol';

const RELAY_URL = import.meta.env.VITE_RELAY_URL;

if (!RELAY_URL) {
  throw new Error('RELAY_URL is not defined in environment variables');
}

function OnlineFlow({ sessionId, optCode }: { sessionId: string; optCode: string }) {
  const signal = useSignalChannel(RELAY_URL, sessionId, 'browser');
  const webrtc = useWebRTC(signal);
  const params = { sessionId, optCode };
  const transfer = useTransfer(params, webrtc);

  if (transfer.state.type === 'error') {
    return <ErrorScreen error={{ code: transfer.state.code, message: transfer.state.message }} retry={transfer.retry} />;
  }

  if (transfer.state.type === 'transferring' || transfer.state.type === 'done') {
    const files = transfer.files.length > 0 ? transfer.files : [];
    const manifest = transfer.manifest ?? [];
    return <ReceiveScreen files={files} manifest={manifest} />;
  }

  const labels: Record<string, string> = {
    connecting: 'Connecting to PC…',
    authenticating: 'Authenticating with PC…',
    booting: 'Loading…',
  };
  const label = labels[transfer.state.type] ?? 'Connecting to PC…';
  return <ConnectingScreen label={label} />;
}

function AppContent() {
  const params = parseShareUrlParams(window.location.search);
  if (!params) {
    return <ErrorScreen error={{ code: 'bad_url', message: 'Missing or invalid share parameters' }} />;
  }

  const [cached, setCached] = useState<{ files: FileProgress[]; manifest: ManifestFileEntry[] } | null>(null);
  const [cacheCheckDone, setCacheCheckDone] = useState(false);

  useEffect(() => {
    let cancelled = false;
    getCachedSession(params.sessionId).then(async (result) => {
      if (cancelled) return;
      if (result && result.session.status === 'complete') {
        const files: FileProgress[] = result.files.map((f) => ({
          index: f.index,
          filename: f.filename,
          content_type: f.contentType,
          size: f.size,
          received: f.size,
          blob: f.blob,
          status: 'done' as const,
        }));

        const manifest: ManifestFileEntry[] = await Promise.all(
          result.files.map(async (f) => {
            const entry: ManifestFileEntry = {
              index: f.index,
              type: f.type,
              content_type: f.contentType,
              size_bytes: f.size,
              filename: f.filename,
            };
            if (f.type === 'text' || f.type === 'link' || f.type === 'html') {
              entry.content = await f.blob.text();
            }
            return entry;
          }),
        );

        if (!cancelled) setCached({ files, manifest });
      }
      if (!cancelled) setCacheCheckDone(true);
    });
    return () => { cancelled = true; };
  }, [params.sessionId]);

  if (!cacheCheckDone) {
    return <ConnectingScreen label="Loading…" />;
  }

  if (cached) {
    return <ReceiveScreen files={cached.files} manifest={cached.manifest} />;
  }

  return <OnlineFlow sessionId={params.sessionId} optCode={params.optCode} />;
}

export default function App() {
  return <AppContent />;
}
```

- [ ] **Step 3: Verify compilation**

Run:
```bash
cd web/instant-share && pnpm exec tsc --noEmit 2>&1
```

Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add web/instant-share/src/App.tsx
git commit -m "feat: check IndexedDB cache on load, skip connection if complete session found"
```

---

### Task 6: Run full test suite and verify

**Files:**
- (none modified — verification only)

- [ ] **Step 1: Run all tests**

```bash
cd web/instant-share && pnpm test -- --run 2>&1
```

Expected: All tests pass, including the new `cache.test.ts` tests.

- [ ] **Step 2: Run type check**

```bash
cd web/instant-share && pnpm exec tsc --noEmit 2>&1
```

Expected: No type errors.

- [ ] **Step 3: Commit (if any fixes were needed)**

If tests or type check passed without changes, no commit needed. Otherwise:

```bash
git add -A
git commit -m "fix: address test/type issues from verification"
```
