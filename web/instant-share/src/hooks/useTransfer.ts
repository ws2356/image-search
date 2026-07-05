import { useEffect, useRef, useState, useCallback } from 'react';
import type { ParsedShareParams } from '../lib/urlParams';
import type { ManifestFileEntry, PayloadType, ControlMessage } from '../lib/protocol';
import { encodeControl, decodeWireEvent } from '../lib/protocol';
import type { UseWebRTCReturn } from './useWebRTC';

export interface FileProgress {
  index: number;
  filename?: string;
  content_type: string;
  size: number;
  received: number;
  blob?: Blob;
  status: 'queued' | 'downloading' | 'done';
}

export type TransferStatus =
  | 'booting' | 'connecting' | 'authenticating'
  | 'transferring' | 'done' | 'error';

export interface TransferError {
  code: string;
  message: string;
}

export interface UseTransferReturn {
  status: TransferStatus;
  error: TransferError | null;
  manifest: ManifestFileEntry[] | null;
  payloadType: PayloadType | null;
  files: FileProgress[];
  retry: () => void;
}

const AUTH_TIMEOUT_MS = 15000;

export function useTransfer(params: ParsedShareParams, webrtc: UseWebRTCReturn): UseTransferReturn {
  const [status, setStatus] = useState<TransferStatus>('connecting');
  const [error, setError] = useState<TransferError | null>(null);
  const [manifest, setManifest] = useState<ManifestFileEntry[] | null>(null);
  const [payloadType, setPayloadType] = useState<PayloadType | null>(null);
  const [files, setFiles] = useState<FileProgress[]>([]);

  const filesRef = useRef<FileProgress[]>([]);
  const currentBinaryRef = useRef<{ index: number; chunks: ArrayBuffer[]; contentType: string; filename: string; size: number } | null>(null);
  const pendingManifestRef = useRef<ManifestFileEntry[] | null>(null);
  const nextDownloadIndexRef = useRef<number>(0);
  const authTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sentAuthRef = useRef(false);

  const fail = useCallback((code: string, message: string) => {
    if (authTimerRef.current) clearTimeout(authTimerRef.current);
    setError({ code, message });
    setStatus('error');
  }, []);

  const sendControl = useCallback((msg: ControlMessage) => {
    const dc = webrtc.channel;
    if (dc && dc.readyState === 'open') {
      dc.send(encodeControl(msg));
    }
  }, [webrtc]);

  const downloadNext = useCallback(() => {
    const pending = pendingManifestRef.current ?? [];
    const idx = nextDownloadIndexRef.current;
    if (idx >= pending.length) {
      setStatus('done');
      return;
    }
    const entry = pending[idx];
    if (entry.type === 'text' || entry.type === 'link' || entry.type === 'html') {
      filesRef.current = filesRef.current.map((f) =>
        f.index === idx ? { ...f, status: 'done', received: f.size } : f,
      );
      setFiles([...filesRef.current]);
      nextDownloadIndexRef.current = idx + 1;
      downloadNext();
      return;
    }
    sendControl({ msg: 'download', index: idx });
  }, [sendControl]);

  const handleMessage = useCallback((data: string | ArrayBuffer) => {
    const ev = decodeWireEvent(data);
    if (!ev) return;
    if (ev.kind === 'binary') {
      if (currentBinaryRef.current) {
        currentBinaryRef.current.chunks.push(ev.buffer);
        filesRef.current = filesRef.current.map((f) =>
          f.index === currentBinaryRef.current!.index
            ? { ...f, received: f.received + ev.buffer.byteLength }
            : f,
        );
        setFiles([...filesRef.current]);
      }
      return;
    }
    const m = ev.message;
    if (m.msg === 'auth_ok') {
      if (authTimerRef.current) clearTimeout(authTimerRef.current);
      setPayloadType(m.payload_type);
      setStatus('transferring');
      sendControl({ msg: 'manifest' });
    } else if (m.msg === 'auth_error') {
      fail('auth_error', m.error);
    } else if (m.msg === 'manifest') {
      const resp = m as { msg: 'manifest'; files: ManifestFileEntry[] };
      pendingManifestRef.current = resp.files;
      nextDownloadIndexRef.current = 0;
      filesRef.current = resp.files.map((f) => ({
        index: f.index,
        filename: f.filename,
        content_type: f.content_type,
        size: f.size_bytes ?? (f.content?.length ?? 0),
        received: 0,
        status: 'queued',
      }));
      setFiles([...filesRef.current]);
      setManifest(resp.files);
      downloadNext();
    } else if (m.msg === 'file_start') {
      currentBinaryRef.current = {
        index: m.index,
        chunks: [],
        contentType: m.content_type,
        filename: m.filename,
        size: m.size,
      };
      filesRef.current = filesRef.current.map((f) =>
        f.index === m.index ? { ...f, status: 'downloading', content_type: m.content_type, filename: m.filename, size: m.size } : f,
      );
      setFiles([...filesRef.current]);
    } else if (m.msg === 'file_end') {
      const cur = currentBinaryRef.current;
      if (cur && cur.index === m.index) {
        const blob = new Blob(cur.chunks, { type: cur.contentType });
        filesRef.current = filesRef.current.map((f) =>
          f.index === m.index ? { ...f, status: 'done', received: f.size, blob } : f,
        );
        setFiles([...filesRef.current]);
        currentBinaryRef.current = null;
        nextDownloadIndexRef.current = m.index + 1;
        downloadNext();
      }
    } else if (m.msg === 'error') {
      fail(m.code, m.message);
    } else if (m.msg === 'bye') {
      setStatus('done');
    }
  }, [sendControl, downloadNext, fail]);

  useEffect(() => {
    const dc = webrtc.channel;
    if (!dc) {
      return;
    }
    if (dc.readyState !== 'open') return;
    if (sentAuthRef.current) return;
    sentAuthRef.current = true;
    setStatus('authenticating');
    sendControl({ msg: 'auth', opt_code: params.optCode });
    authTimerRef.current = setTimeout(() => {
      fail('auth_timeout', 'Authentication timed out');
    }, AUTH_TIMEOUT_MS);

    const onMessage = (e: MessageEvent) => handleMessage(e.data);
    const onClose = () => {
      setStatus((prev) => (prev === 'done' || prev === 'error') ? prev : 'error');
      setError((prev) => prev ?? { code: 'disconnected', message: 'Connection lost' });
    };
    dc.addEventListener('message', onMessage);
    dc.addEventListener('close', onClose);
    return () => {
      dc.removeEventListener('message', onMessage);
      dc.removeEventListener('close', onClose);
      if (authTimerRef.current) clearTimeout(authTimerRef.current);
    };
  }, [webrtc, params.optCode, sendControl, handleMessage, fail]);

  useEffect(() => {
    if (webrtc.state === 'failed') {
      fail('disconnected', 'Connection failed');
    } else if (webrtc.state === 'closed' && status !== 'done' && status !== 'error') {
      fail('disconnected', 'Connection closed');
    }
  }, [webrtc.state, fail, status]);

  const retry = useCallback(() => {
    webrtc.close();
    setError({ code: 'rescan', message: 'Please re-scan the QR code to retry.' });
    setStatus('error');
  }, [webrtc]);

  return { status, error, manifest, payloadType, files, retry };
}
