import { useEffect, useRef, useState, useCallback } from 'react';
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

  const handleSignalEvent = useCallback((e: SignalEvent) => {
    const pc = pcRef.current;
    if (!pc) return;

    if (e.type === 'offer') {
      pc.setRemoteDescription({ type: 'offer', sdp: e.sdp })
        .then(async () => {
          const answer = await pc.createAnswer({ offerToReceiveData: true } as RTCOfferOptions);
          await pc.setLocalDescription(answer);
          signal.send({ type: 'answer', sdp: answer.sdp });
          setState('connecting');
        })
        .catch(() => setState('failed'));
    } else if (e.type === 'answer') {
      pc.setRemoteDescription({ type: 'answer', sdp: e.sdp })
        .catch(() => setState('failed'));
    } else if (e.type === 'candidate') {
      pc.addIceCandidate(e.candidate).catch(() => {});
    } else if (e.type === 'peer_left' || e.type === 'room_full') {
      setState('closed');
    }
  }, [signal]);

  useEffect(() => {
    const pc = new RTCPeerConnection({ iceServers: [] });
    pcRef.current = pc;

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        signal.send({ type: 'candidate', candidate: event.candidate.toJSON() });
      }
    };
    pc.onconnectionstatechange = () => {
      const s = pc.connectionState;
      if (s === 'connected') setState((prev) => (prev === 'open' ? 'open' : 'connecting'));
      else if (s === 'disconnected' || s === 'failed') setState('failed');
      else if (s === 'closed') setState('closed');
    };
    pc.ondatachannel = (event) => {
      const dc = event.channel;
      dc.binaryType = 'arraybuffer';
      channelRef.current = dc;
      dc.onopen = () => setState('open');
      dc.onclose = () => setState('closed');
      setChannel(dc);
    };

    const unsubscribe = signal.onEvent(handleSignalEvent);
    return () => {
      unsubscribe();
      try { channelRef.current?.close(); } catch {}
      try { pc.close(); } catch {}
      pcRef.current = null;
      channelRef.current = null;
      setChannel(null);
    };
  }, [signal, handleSignalEvent]);

  const close = useCallback(() => {
    try { channelRef.current?.close(); } catch {}
    try { pcRef.current?.close(); } catch {}
    signal.send({ type: 'leave' });
    signal.close();
  }, [signal]);

  return { channel, state, close };
}
