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
