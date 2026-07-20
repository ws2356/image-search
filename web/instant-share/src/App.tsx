import React, { useState, useEffect, Suspense } from 'react';
import { parseShareUrlParams } from './lib/urlParams';
import { useSignalChannel } from './hooks/useSignalChannel';
import { useWebRTC } from './hooks/useWebRTC';
import { useTransfer, type FileProgress } from './hooks/useTransfer';
import { ConnectingScreen } from './components/ConnectingScreen';
import { ErrorScreen } from './components/ErrorScreen';
import { WeChatScreen } from './components/WeChatScreen';
import { log } from './lib/log';
import { isWeChatWebview } from './lib/env';
import { getCachedSession, cleanExpired } from './services/cache';
import type { ManifestFileEntry } from './lib/protocol';

const ReceiveScreen = React.lazy(() => import('./components/ReceiveScreen').then(m => ({ default: m.ReceiveScreen })));

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
    return (
      <Suspense fallback={<ConnectingScreen label="Loading…" />}>
        <ReceiveScreen files={files} manifest={manifest} />
      </Suspense>
    );
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
    log.warn('App: invalid or missing URL params');
    return <ErrorScreen error={{ code: 'bad_url', message: 'Missing or invalid share parameters' }} />;
  }

  const [cached, setCached] = useState<{ files: FileProgress[]; manifest: ManifestFileEntry[] } | null>(null);
  const [cacheCheckDone, setCacheCheckDone] = useState(false);

  useEffect(() => {
    if ('requestIdleCallback' in window) {
      (window as unknown as { requestIdleCallback: (cb: () => void) => void }).requestIdleCallback(() => cleanExpired().catch(() => {}));
    } else {
      setTimeout(() => cleanExpired().catch(() => {}), 0);
    }

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
    return (
      <Suspense fallback={<ConnectingScreen label="Loading…" />}>
        <ReceiveScreen files={cached.files} manifest={cached.manifest} />
      </Suspense>
    );
  }

  if (isWeChatWebview()) {
    log.warn('App: WeChat webview detected, aborting WebRTC flow');
    return <WeChatScreen />;
  }

  return <OnlineFlow sessionId={params.sessionId} optCode={params.optCode} />;
}

export default function App() {
  return <AppContent />;
}
