#!/usr/bin/env node
// Mock PC WebRTC peer for integration testing against the deployed relay.
// Usage: node scripts/mock-pc-peer.mjs <sessionId> <optCode> <relayUrl>
import { RTCPeerConnection } from '@rohub/wrtc';
import { WebSocket } from 'ws';

const [sid, optCode, relayUrl] = process.argv.slice(2);
if (!sid || !optCode) {
  console.error('Usage: node mock-pc-peer.mjs <sessionId> <optCode> [relayUrl]');
  process.exit(1);
}
const url = (relayUrl ?? 'wss://dl.boldman.net/relay') + `?sid=${encodeURIComponent(sid)}&role=pc`;

const ws = new WebSocket(url);
const pc = new RTCPeerConnection({ iceServers: [] });
const dc = pc.createDataChannel('share');
dc.binaryType = 'arraybuffer';

dc.onmessage = (event) => {
  if (typeof event.data !== 'string') return;
  const msg = JSON.parse(event.data);
  console.log('PC recv:', msg);
  if (msg.msg === 'auth') {
    if (msg.opt_code === optCode) {
      dc.send(JSON.stringify({ msg: 'auth_ok', session_id: sid, file_count: 1, payload_type: 'file' }));
    } else {
      dc.send(JSON.stringify({ msg: 'auth_error', error: 'invalid_opt' }));
    }
  } else if (msg.msg === 'manifest') {
    dc.send(JSON.stringify({ msg: 'manifest', files: [{ index: 0, type: 'file', filename: 'hello.txt', content_type: 'text/plain', size_bytes: 5 }] }));
  } else if (msg.msg === 'download' && msg.index === 0) {
    dc.send(JSON.stringify({ msg: 'file_start', index: 0, content_type: 'text/plain', filename: 'hello.txt', size: 5 }));
    dc.send(Buffer.from('hello'));
    dc.send(JSON.stringify({ msg: 'file_end', index: 0 }));
  }
};

pc.onicecandidate = (e) => {
  if (e.candidate) ws.send(JSON.stringify({ type: 'candidate', candidate: e.candidate.toJSON() }));
};

ws.on('open', async () => {
  ws.send(JSON.stringify({ type: 'join', sid, role: 'pc' }));
  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  ws.send(JSON.stringify({ type: 'offer', sdp: offer.sdp }));
});

ws.on('message', async (raw) => {
  const data = JSON.parse(raw.toString());
  if (data.type === 'answer') {
    await pc.setRemoteDescription({ type: 'answer', sdp: data.sdp });
  } else if (data.type === 'candidate') {
    try { await pc.addIceCandidate(data.candidate); } catch {}
  } else if (data.type === 'peer_left') {
    console.log('peer left');
    process.exit(0);
  }
});

ws.on('close', () => process.exit(0));
