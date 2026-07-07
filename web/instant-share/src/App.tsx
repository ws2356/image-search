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
    return <ReceiveScreen files={files} manifest={manifest} />;
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