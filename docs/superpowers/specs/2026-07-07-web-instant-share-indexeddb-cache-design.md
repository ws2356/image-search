# Web Instant Share — IndexedDB Session Cache

**Date:** 2026-07-07
**Status:** Design approved, implementation pending
**Author:** Brainstorming session (opencode + ws2356)

## Purpose

After the web instant-share SPA receives files successfully via WebRTC, it
should persist them in IndexedDB so that reloading the page (or revisiting the
same share URL) displays the received content instantly, without reconnecting to
the signaling relay or re-establishing a WebRTC connection.

## Context

The web instant-share SPA receives files over a WebRTC data channel. Currently
all received data lives only in React component state — a page reload loses
everything. The user wants offline-accessible cached sessions.

## Decisions (from brainstorming)

- **Cache-only on reload**: Once a session is cached as `complete`, the SPA
  never reconnects to the signaling relay or WebRTC for that sessionId.
- **TTL**: 7 days from the `completedAt` timestamp. Expired sessions are
  deleted on DB open.
- **Partial/transferring sessions**: Ignored on reload. If the user reloads
  mid-transfer, the partial cache is effectively orphaned until expiry cleanup
  removes it.
- **Inline content**: Text, link, and HTML payloads are UTF-8-encoded to Blobs
  and stored identically to binary files in the `files` store.

## Data Model

Two IndexedDB object stores in a single database named `instant-share-cache`.

### `sessions` (key path: `sessionId`)

| Field | Type | Notes |
|---|---|---|
| `sessionId` | string | URL param `sid` |
| `status` | `'transferring'` \| `'complete'` | |
| `completedAt` | number | `Date.now()` when status → `complete`; `null` while transferring |

### `files` (auto-increment key, indexed by `sessionId`)

| Field | Type | Notes |
|---|---|---|
| `id` | auto-increment | |
| `sessionId` | string | indexed |
| `index` | number | position in manifest order |
| `type` | `'text'` \| `'link'` \| `'html'` \| `'file'` | |
| `contentType` | string | MIME type |
| `filename` | string | |
| `size` | number | bytes |
| `blob` | Blob | natively stored; for text/link/html, UTF-8 Blob |

## Service Layer

### `src/services/cache.ts` (new)

A module exporting async functions. The IndexedDB connection is lazy
(initialized on first call), cached at module scope, and versioned.

```
openDB(): Promise<IDBDatabase>
  - Opens (or creates) the database, runs cleanExpired internally
  - On upgrade: creates sessions and files object stores + index

saveFile(sessionId, entry): Promise<void>
  - Creates/upserts the session row (status='transferring') if it doesn't exist
  - Inserts a file row with the given blob

completeSession(sessionId): Promise<void>
  - Updates the session: status='complete', completedAt=Date.now()

getCachedSession(sessionId): Promise<{ session, files } | null>
  - Reads the session row and all its files from the `files` index
  - Returns null if no session record exists (never saved) or if expired
  - Returns raw data so the caller inspects `session.status` to decide behavior

cleanExpired(): Promise<void>
  - Deletes sessions where (Date.now() - completedAt) > 7 days
  - Also deletes their associated files
  - Called once on DB open and could be called periodically if needed
```

### `src/services/cache.test.ts` (new)

Unit tests using fake-indexeddb or jsdom's IDBFactory mock to cover:
- Round-trip: save files → complete → getCachedSession returns correct data
- Transferring sessions are returned (status: 'transferring')
- Expired sessions return null from getCachedSession
- cleanExpired removes expired sessions + cascades to files
- Concurrent writes (multiple files) don't conflict

## Integration Points

### `src/hooks/useTransfer.ts` (modified)

- When a binary file finishes downloading (`file_end` message): call
  `cache.saveFile(sessionId, { ...file, blob })`.
- When inline content (text/link/html) is extracted from the manifest:
  encode content as `new Blob([content], { type: mimeType })`, call
  `cache.saveFile(...)`.
- In the `bye` / all-downloads-complete path: call
  `cache.completeSession(sessionId)` before sending `bye` and setting state to
  `done`.

All cache writes are fire-and-forget from the transfer hook's perspective —
the cache is an observer of the transfer, not a participant in the protocol.

### `src/App.tsx` (modified)

Before initializing `useSignalChannel` / `useWebRTC` / `useTransfer`:

1. Call `getCachedSession(sessionId)`.
2. If returned and `session.status === 'complete'`:
   - Reconstruct `FileProgress[]` from cached files (all `status: 'done'`).
   - Reconstruct `ManifestFileEntry[]` with inline content decoded back from
     Blobs.
   - Set transfer state to `done` directly.
   - Skip all connection hooks (signal, WebRTC, transfer).
3. If `null` or `session.status === 'transferring'`: proceed with the normal
   connection flow.

### `src/components/ReceiveScreen.tsx` (no changes)

The ReceiveScreen receives the same `files` and `manifest` props regardless of
whether data came from cache or a live WebRTC transfer. No UI changes needed.

## Error Handling

- **IndexedDB unavailable / private browsing**: `openDB` returns a no-op
  database or the hooks catch the error and log a warning — the transfer
  proceeds normally without caching. No error surface to the user.
- **Quota exceeded**: `saveFile` catches the error, logs a warning, and does
  not mark the session as complete (so the partial cache is ignored on reload).
  Transfer still completes successfully from the user's perspective.
- **DB upgrade conflicts**: Handled by IndexedDB's `onblocked` event; unlikely
  in a single-tab SPA.
