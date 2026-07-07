import { useEffect, useRef, useState, useCallback } from 'react';
import { log } from '../lib/log';
import type { UseSignalChannelReturn, SignalEvent } from './useSignalChannel';

export interface UseWebRTCReturn {
  channel: RTCDataChannel | null;
  state: 'new' | 'connecting' | 'open' | 'closed' | 'failed';
  close: () => void;
}

const ICE_CONFIG: RTCConfiguration = {
  iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
  iceCandidatePoolSize: 10,
};

export function useWebRTC(signal: UseSignalChannelReturn): UseWebRTCReturn {
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const channelRef = useRef<RTCDataChannel | null>(null);
  const [channel, setChannel] = useState<RTCDataChannel | null>(null);
  const [state, setState] = useState<UseWebRTCReturn['state']>('new');
  const signalSend = useCallback((msg: object) => signal.send(msg), [signal.send]);

  const handleSignalEvent = useCallback((e: SignalEvent) => {
    const pc = pcRef.current;
    if (!pc) {
      log.warn('useWebRTC: signal event dropped, no pc', e.type);
      return;
    }

    if (e.type === 'offer') {
      log.info('useWebRTC: received offer, setting remote description');
      pc.setRemoteDescription({ type: 'offer', sdp: e.sdp })
        .then(async () => {
          log.info('useWebRTC: remote desc set, creating answer', {
            iceGathering: pc.iceGatheringState,
            iceConn: pc.iceConnectionState,
          });
          const answer = await pc.createAnswer();
          log.info('useWebRTC: answer created', {
            sdpLen: answer.sdp?.length,
            hasCandidates: (answer.sdp?.match(/a=candidate:/g) || []).length,
          });
          await pc.setLocalDescription(answer);
          log.info('useWebRTC: local desc set', { iceGathering: pc.iceGatheringState });

          if (pc.iceGatheringState !== 'complete') {
            await new Promise<void>((resolve) => {
              const check = () => {
                log.info('useWebRTC: icegatheringstatechange', { state: pc.iceGatheringState });
                if (pc.iceGatheringState === 'complete') {
                  pc.removeEventListener('icegatheringstatechange', check);
                  resolve();
                }
              };
              pc.addEventListener('icegatheringstatechange', check);
              setTimeout(() => {
                if (pc.iceGatheringState !== 'complete') {
                  log.warn('useWebRTC: ICE gathering timeout after 5s, sending answer anyway');
                }
                pc.removeEventListener('icegatheringstatechange', check);
                resolve();
              }, 5000);
            });
          }

          const finalSdp = pc.localDescription?.sdp ?? '';
          const candidateCount = (finalSdp.match(/a=candidate:/g) || []).length;
          log.info('useWebRTC: sending answer', {
            sdpLength: finalSdp.length,
            candidateCount,
            iceState: pc.iceGatheringState,
          });
          if (candidateCount === 0) {
            log.warn('useWebRTC: ZERO candidates in answer SDP — ICE will fail');
          }
          signalSend({ type: 'answer', sdp: finalSdp });
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
      log.info('useWebRTC: adding ice candidate from PC');
      pc.addIceCandidate(e.candidate)
        .then(() => log.info('useWebRTC: ice candidate added OK'))
        .catch((err) => log.warn('useWebRTC: ice candidate rejected', err));
    } else if (e.type === 'peer_left' || e.type === 'room_full') {
      log.warn('useWebRTC: peer left or room full, closing all', e.type);
      try { channelRef.current?.close(); } catch {}
      try { pcRef.current?.close(); } catch {}
      pcRef.current = null;
      channelRef.current = null;
      setState('closed');
      signal.close();
    }
  }, [signalSend]);

  useEffect(() => {
    log.info('useWebRTC: creating RTCPeerConnection', { config: ICE_CONFIG });
    const pc = new RTCPeerConnection(ICE_CONFIG);
    pcRef.current = pc;

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        log.info('useWebRTC: ice candidate gathered', event.candidate.candidate);
      } else {
        log.info('useWebRTC: ice gathering complete (onicecandidate=null)');
      }
    };
    pc.onicegatheringstatechange = () => {
      log.info('useWebRTC: ice gathering state changed', pc.iceGatheringState);
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
      log.info('useWebRTC: cleanup, closing pc', { connState: pc.connectionState });
      unsubscribe();
      try { channelRef.current?.close(); } catch {}
      try { pc.close(); } catch {}
      pcRef.current = null;
      channelRef.current = null;
    };
  }, [signal.onEvent, handleSignalEvent, signalSend]);

  const close = useCallback(() => {
    log.info('useWebRTC: close called');
    try { channelRef.current?.close(); } catch {}
    try { pcRef.current?.close(); } catch {}
    signal.close();
  }, [signal]);

  return { channel, state, close };
}
