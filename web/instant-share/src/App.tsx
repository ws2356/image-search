import { parseShareUrlParams } from './lib/urlParams';
import { useSignalChannel } from './hooks/useSignalChannel';
import { useWebRTC } from './hooks/useWebRTC';
import { useTransfer } from './hooks/useTransfer';
import { ConnectingScreen } from './components/ConnectingScreen';
import { TransferScreen } from './components/TransferScreen';
import { DoneScreen } from './components/DoneScreen';
import { ErrorScreen } from './components/ErrorScreen';

const RELAY_URL = 'wss://dl.boldman.net/relay';

function AppContent() {
  const params = parseShareUrlParams(window.location.search);
  if (!params) {
    return <ErrorScreen error={{ code: 'bad_url', message: 'Missing or invalid share parameters' }} />;
  }

  const signal = useSignalChannel(RELAY_URL, params.sessionId, 'browser');
  const webrtc = useWebRTC(signal);
  const transfer = useTransfer(params, webrtc);

  if (transfer.status === 'done') return <DoneScreen />;
  if (transfer.status === 'error') return <ErrorScreen error={transfer.error ?? { code: 'unknown', message: '' }} />;
  if (transfer.status === 'transferring' && transfer.files.length > 0 && transfer.manifest) {
    return <TransferScreen files={transfer.files} manifest={transfer.manifest} />;
  }
  const labels: Record<string, string> = {
    connecting: 'Connecting to PC…',
    authenticating: 'Authenticating with PC…',
    booting: 'Loading…',
  };
  return <ConnectingScreen label={labels[transfer.status] ?? 'Connecting to PC…'} />;
}

export default function App() {
  return <AppContent />;
}
