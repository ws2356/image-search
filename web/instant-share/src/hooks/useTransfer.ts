import { useEffect, useRef, useState, useCallback } from 'react';
import { log } from '../lib/log';
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
    log.error('useTransfer: fail', { code, message });
    if (authTimerRef.current) clearTimeout(authTimerRef.current);
    setError({ code, message });
    setStatus('error');
  }, []);

  const sendControl = useCallback((msg: ControlMessage) => {
    const dc = webrtc.channel;
    if (!dc) {
      log.warn('useTransfer: sendControl skipped, no dc', msg.msg);
      return;
    }
    if (dc.readyState !== 'open') {
      log.warn('useTransfer: sendControl skipped, dc not open', { state: dc.readyState, msg: msg.msg });
      return;
    }
    log.debug('useTransfer: sendControl', msg.msg);
    dc.send(encodeControl(msg));
  }, [webrtc]);

  const downloadNext = useCallback(() => {
    const pending = pendingManifestRef.current ?? [];
    const idx = nextDownloadIndexRef.current;
    if (idx >= pending.length) {
      log.info('useTransfer: all downloads complete, status=done');
      setStatus('done');
      return;
    }
    const entry = pending[idx];
    log.info('useTransfer: downloadNext', { idx, type: entry.type, filename: entry.filename });
    if (entry.type === 'text' || entry.type === 'link' || entry.type === 'html') {
      log.info('useTransfer: inline content, marking done', { idx, type: entry.type });
      filesRef.current = filesRef.current.map((f) =>
        f.index === idx ? { ...f, status: 'done', received: f.size } : f,
      );
      setFiles([...filesRef.current]);
      nextDownloadIndexRef.current = idx + 1;
      downloadNext();
      return;
    }
    log.info('useTransfer: requesting download', { idx });
    sendControl({ msg: 'download', index: idx });
  }, [sendControl]);

  const handleMessage = useCallback((data: string | ArrayBuffer) => {
    const ev = decodeWireEvent(data);
    if (!ev) {
      log.warn('useTransfer: handleMessage: decodeWireEvent returned null');
      return;
    }
    if (ev.kind === 'binary') {
      if (currentBinaryRef.current) {
        currentBinaryRef.current.chunks.push(ev.buffer);
        const total = currentBinaryRef.current.chunks.reduce((s, c) => s + c.byteLength, 0);
        log.debug('useTransfer: binary chunk', { index: currentBinaryRef.current.index, chunkBytes: ev.buffer.byteLength, totalBytes: total });
        filesRef.current = filesRef.current.map((f) =>
          f.index === currentBinaryRef.current!.index
            ? { ...f, received: f.received + ev.buffer.byteLength }
            : f,
        );
        setFiles([...filesRef.current]);
      } else {
        log.warn('useTransfer: binary chunk received but no current download');
      }
      return;
    }
    const m = ev.message;
    log.info('useTransfer: control msg', m.msg, m);
    if (m.msg === 'auth_ok') {
      if (authTimerRef.current) clearTimeout(authTimerRef.current);
      log.info('useTransfer: auth ok', { payload_type: m.payload_type });
      setPayloadType(m.payload_type);
      setStatus('transferring');
      sendControl({ msg: 'manifest' });
    } else if (m.msg === 'auth_error') {
      log.warn('useTransfer: auth_error', m.error);
      fail('auth_error', m.error);
    } else if (m.msg === 'manifest') {
      const resp = m as { msg: 'manifest'; files: ManifestFileEntry[] };
      log.info('useTransfer: manifest received', { fileCount: resp.files.length, types: resp.files.map(f => f.type) });
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
      log.info('useTransfer: file_start', { index: m.index, filename: m.filename, size: m.size, content_type: m.content_type });
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
        const totalBytes = cur.chunks.reduce((s, c) => s + c.byteLength, 0);
        const blob = new Blob(cur.chunks, { type: cur.contentType });
        log.info('useTransfer: file_end', { index: m.index, totalBytes, expected: cur.size });
        filesRef.current = filesRef.current.map((f) =>
          f.index === m.index ? { ...f, status: 'done', received: f.size, blob } : f,
        );
        setFiles([...filesRef.current]);
        currentBinaryRef.current = null;
        nextDownloadIndexRef.current = m.index + 1;
        downloadNext();
      } else {
        log.warn('useTransfer: file_end mismatch', { index: m.index, hasCurrent: !!cur });
      }
    } else if (m.msg === 'error') {
      log.error('useTransfer: peer error', { code: m.code, message: m.message });
      fail(m.code, m.message);
    } else if (m.msg === 'bye') {
      log.info('useTransfer: bye received');
      setStatus('done');
    }
  }, [sendControl, downloadNext, fail]);

  useEffect(() => {
    const dc = webrtc.channel;
    if (!dc) {
      return;
    }
    log.info('useTransfer: dc available', { readyState: dc.readyState });
    if (dc.readyState !== 'open') {
      log.info('useTransfer: dc not open yet, waiting', { state: dc.readyState });
      return;
    }
    if (sentAuthRef.current) {
      log.debug('useTransfer: auth already sent, skipping');
      return;
    }
    sentAuthRef.current = true;
    log.info('useTransfer: sending auth', { optCode: '***' });
    setStatus('authenticating');
    sendControl({ msg: 'auth', opt_code: params.optCode });
    authTimerRef.current = setTimeout(() => {
      log.error('useTransfer: auth timeout (15s)');
      fail('auth_timeout', 'Authentication timed out');
    }, AUTH_TIMEOUT_MS);

    const onMessage = (e: MessageEvent) => handleMessage(e.data);
    const onClose = () => {
      log.warn('useTransfer: dc closed');
      setStatus((prev) => (prev === 'done' || prev === 'error') ? prev : 'error');
      setError((prev) => prev ?? { code: 'disconnected', message: 'Connection lost' });
    };
    dc.addEventListener('message', onMessage);
    dc.addEventListener('close', onClose);
    return () => {
      log.debug('useTransfer: removing dc listeners');
      dc.removeEventListener('message', onMessage);
      dc.removeEventListener('close', onClose);
      if (authTimerRef.current) clearTimeout(authTimerRef.current);
    };
  }, [webrtc, params.optCode, sendControl, handleMessage, fail]);

  useEffect(() => {
    if (webrtc.state === 'failed') {
      log.warn('useTransfer: webrtc.state=failed');
      fail('disconnected', 'Connection failed');
    } else if (webrtc.state === 'closed' && status !== 'done' && status !== 'error') {
      log.warn('useTransfer: webrtc.state=closed');
      fail('disconnected', 'Connection closed');
    }
  }, [webrtc.state, fail, status]);

  const retry = useCallback(() => {
    log.info('useTransfer: retry');
    webrtc.close();
    setError({ code: 'rescan', message: 'Please re-scan the QR code to retry.' });
    setStatus('error');
  }, [webrtc]);

  return { status, error, manifest, payloadType, files, retry };
}
