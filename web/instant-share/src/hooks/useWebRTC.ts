import { useEffect, useRef, useState, useCallback } from 'react';
import { log } from '../lib/log';
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
  const stateRef = useRef(state);
  stateRef.current = state;

  const handleSignalEvent = useCallback((e: SignalEvent) => {
    const pc = pcRef.current;
    if (!pc) {
      log.warn('useWebRTC: signal event dropped, no pc', e.type);
      return;
    }

    if (e.type === 'offer') {
      log.info('useWebRTC: setting remote offer, creating answer');
      pc.setRemoteDescription({ type: 'offer', sdp: e.sdp })
        .then(async () => {
          log.info('useWebRTC: remote desc set, creating answer');
          const answer = await pc.createAnswer({ offerToReceiveData: true } as RTCOfferOptions);
          log.info('useWebRTC: sending answer');
          await pc.setLocalDescription(answer);
          signal.send({ type: 'answer', sdp: answer.sdp });
          setState('connecting');
        })
        .catch((err) => {
          log.error('useWebRTC: offer/answer failed', err);
          setState('failed');
        });
    } else if (e.type === 'answer') {
      log.info('useWebRTC: setting remote answer');
      pc.setRemoteDescription({ type: 'answer', sdp: e.sdp })
        .then(() => log.info('useWebRTC: remote answer set'))
        .catch((err) => {
          log.error('useWebRTC: setRemoteDescription failed', err);
          setState('failed');
        });
    } else if (e.type === 'candidate') {
      log.debug('useWebRTC: adding ice candidate');
      pc.addIceCandidate(e.candidate)
        .then(() => log.debug('useWebRTC: ice candidate added'))
        .catch((err) => log.warn('useWebRTC: ice candidate rejected', err));
    } else if (e.type === 'peer_left' || e.type === 'room_full') {
      log.warn('useWebRTC: peer left or room full', e.type);
      setState('closed');
    }
  }, [signal]);

  useEffect(() => {
    log.info('useWebRTC: creating RTCPeerConnection');
    const pc = new RTCPeerConnection({ iceServers: [] });
    pcRef.current = pc;

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        log.debug('useWebRTC: sending ice candidate');
        signal.send({ type: 'candidate', candidate: event.candidate.toJSON() });
      } else {
        log.info('useWebRTC: ice gathering complete');
      }
    };
    pc.onicegatheringstatechange = () => {
      log.debug('useWebRTC: ice gathering state', pc.iceGatheringState);
    };
    pc.oniceconnectionstatechange = () => {
      log.info('useWebRTC: ice connection state', pc.iceConnectionState);
    };
    pc.onconnectionstatechange = () => {
      const s = pc.connectionState;
      log.info('useWebRTC: connection state', s);
      if (s === 'connected') setState((prev) => (prev === 'open' ? 'open' : 'connecting'));
      else if (s === 'disconnected' || s === 'failed') {
        log.warn('useWebRTC: connection failed or disconnected', s);
        setState('failed');
      }
      else if (s === 'closed') setState('closed');
    };
    pc.ondatachannel = (event) => {
      const dc = event.channel;
      dc.binaryType = 'arraybuffer';
      channelRef.current = dc;
      log.info('useWebRTC: received data channel', { label: dc.label, id: dc.id });
      dc.onopen = () => {
        log.info('useWebRTC: data channel open');
        setState('open');
      };
      dc.onclose = () => {
        log.info('useWebRTC: data channel closed');
        setState('closed');
      };
      dc.onerror = (err) => {
        log.error('useWebRTC: data channel error', err);
      };
      setChannel(dc);
    };

    const unsubscribe = signal.onEvent(handleSignalEvent);
    return () => {
      log.info('useWebRTC: cleanup');
      unsubscribe();
      try { channelRef.current?.close(); } catch {}
      try { pc.close(); } catch {}
      pcRef.current = null;
      channelRef.current = null;
      setChannel(null);
    };
  }, [signal, handleSignalEvent]);

  const close = useCallback(() => {
    log.info('useWebRTC: close called');
    try { channelRef.current?.close(); } catch {}
    try { pcRef.current?.close(); } catch {}
    signal.send({ type: 'leave' });
    signal.close();
  }, [signal]);

  return { channel, state, close };
}
