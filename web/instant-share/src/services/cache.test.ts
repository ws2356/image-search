import { describe, it, expect, beforeEach } from 'vitest';
import { openDB, saveFile, completeSession, getCachedSession, cleanExpired, closeDB } from './cache';
import type { FileEntryInput } from './cache';

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

beforeEach(async () => {
  closeDB();
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
