import { useEffect, useRef, useState, useCallback } from 'react';
import { log } from '../lib/log';

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
  const closedByUser = useRef(false);
  const sidShort = sessionId.slice(0, 8);
  const paramsKey = `${relayUrl}|${sessionId}|${role}`;
  const prevParamsKey = useRef(paramsKey);

  const emit = useCallback((e: SignalEvent) => {
    handlersRef.current.forEach((h) => h(e));
  }, []);

  useEffect(() => {
    const existing = wsRef.current;
    if (existing && prevParamsKey.current === paramsKey) {
      if (existing.readyState === WebSocket.CONNECTING || existing.readyState === WebSocket.OPEN) {
        log.info('useSignalChannel: remount, reusing existing ws', { role, sidShort });
        existing.onmessage = (event) => {
          if (typeof event.data !== 'string') return;
          let parsed: any;
          try { parsed = JSON.parse(event.data); } catch { return; }
          log.debug('useSignalChannel: relay msg', parsed.type, role, sidShort);
          if (parsed.type === 'joined') {
            log.info('useSignalChannel: joined relay', { role: parsed.role, sidShort });
            setReady(true);
            emit({ type: 'joined', role: parsed.role });
            return;
          }
          if (parsed.type === 'peer_left') { log.info('useSignalChannel: peer_left', { sidShort }); emit({ type: 'peer_left' }); return; }
          if (parsed.type === 'room_full') { log.warn('useSignalChannel: room_full', { sidShort }); emit({ type: 'room_full' }); return; }
          if (parsed.type === 'offer') { log.info('useSignalChannel: received offer', { sidShort }); emit({ type: 'offer', sdp: parsed.sdp }); return; }
          if (parsed.type === 'answer') { log.info('useSignalChannel: received answer', { sidShort }); emit({ type: 'answer', sdp: parsed.sdp }); return; }
          if (parsed.type === 'candidate') { log.debug('useSignalChannel: received candidate', { sidShort }); emit({ type: 'candidate', candidate: parsed.candidate }); return; }
        };
        return;
      }
      try { existing.close(); } catch {}
      wsRef.current = null;
    }

    prevParamsKey.current = paramsKey;
    log.info('useSignalChannel: connecting', { role, sidShort, relayUrl });
    const ws = new WebSocket(`${relayUrl}?sid=${encodeURIComponent(sessionId)}&role=${role}`);
    wsRef.current = ws;

    ws.onopen = () => {
      log.info('useSignalChannel: ws open, sending join', { role, sidShort });
      ws.send(JSON.stringify({ type: 'join', sid: sessionId, role }));
    };
    ws.onmessage = (event) => {
      if (typeof event.data !== 'string') return;
      let parsed: any;
      try { parsed = JSON.parse(event.data); } catch { return; }
      log.debug('useSignalChannel: relay msg', parsed.type, role, sidShort);
      if (parsed.type === 'joined') {
        log.info('useSignalChannel: joined relay', { role: parsed.role, sidShort });
        setReady(true);
        emit({ type: 'joined', role: parsed.role });
        return;
      }
      if (parsed.type === 'peer_left') { log.info('useSignalChannel: peer_left', { sidShort }); emit({ type: 'peer_left' }); return; }
      if (parsed.type === 'room_full') { log.warn('useSignalChannel: room_full', { sidShort }); emit({ type: 'room_full' }); return; }
      if (parsed.type === 'offer') { log.info('useSignalChannel: received offer', { sidShort }); emit({ type: 'offer', sdp: parsed.sdp }); return; }
      if (parsed.type === 'answer') { log.info('useSignalChannel: received answer', { sidShort }); emit({ type: 'answer', sdp: parsed.sdp }); return; }
      if (parsed.type === 'candidate') { log.debug('useSignalChannel: received candidate', { sidShort }); emit({ type: 'candidate', candidate: parsed.candidate }); return; }
    };
    ws.onerror = () => { log.error('useSignalChannel: ws error', { sidShort }); emit({ type: 'error', message: 'Relay connection error' }); };
    ws.onclose = (e) => {
      log.info('useSignalChannel: ws closed', { code: e.code, reason: e.reason, sidShort });
      setReady(false);
      if (!closedByUser.current) {
        emit({ type: 'peer_left' });
      }
    };

    return () => {
      log.info('useSignalChannel: remount cleanup, not closing ws', { sidShort });
    };
  }, [relayUrl, sessionId, role, emit, sidShort, paramsKey]);

  const send = useCallback((msg: object) => {
    log.debug('useSignalChannel: send', (msg as any).type, sidShort);
    wsRef.current?.send(JSON.stringify(msg));
  }, [sidShort]);

  const onEvent = useCallback((handler: (e: SignalEvent) => void) => {
    handlersRef.current.add(handler);
    return () => { handlersRef.current.delete(handler); };
  }, []);

  const close = useCallback(() => {
    log.info('useSignalChannel: close', { sidShort });
    closedByUser.current = true;
    wsRef.current?.close();
  }, [sidShort]);

  return { ready, send, onEvent, close };
}
