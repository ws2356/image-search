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
      resolve(request.result);
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

    sessionStore.put({ sessionId, status: 'transferring', completedAt: null });
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

export function closeDB(): void {
  if (dbPromise) {
    dbPromise.then((db) => {
      try { db.close(); } catch { /* ignore */ }
    });
    dbPromise = null;
  }
}
