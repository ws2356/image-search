import { WebSocketServer } from 'ws';
import { createServer } from 'http';

export function createRelay(port, opts) {
  const reconnectGraceMs = opts?.reconnectGraceMs ?? parseInt(process.env.RECONNECT_GRACE_MS ?? '3000', 10);
  const rooms = new Map();

  function getRoom(sid) {
    if (!rooms.has(sid)) rooms.set(sid, { pc: null, browser: null, _buffer: [] });
    return rooms.get(sid);
  }

  const server = createServer();
  const wss = new WebSocketServer({ server });

  function sidShort(sid) { return sid.slice(0, 8); }

  wss.on('connection', (ws, req) => {
    const url = new URL(req.url ?? '/', 'http://x');
    const sid = url.searchParams.get('sid');
    const role = url.searchParams.get('role');

    if (!sid || (role !== 'pc' && role !== 'browser')) {
      console.log(`[relay] REJECT invalid params sid=${sid} role=${role}`);
      ws.close(4001, 'invalid params');
      return;
    }

    const room = getRoom(sid);
    const ss = sidShort(sid);

    if (role === 'pc') {
      if (room.pc && room.pc.readyState === WebSocket.OPEN) {
        console.log(`[relay] REJECT room_full sid=${ss} role=pc`);
        ws.close(4002, 'room_full'); return;
      }
      if (room._pcReconnectTimer) { clearTimeout(room._pcReconnectTimer); room._pcReconnectTimer = null; }
      room.pc = ws;
      console.log(`[relay] CONNECT sid=${ss} role=pc bufferLen=${room._buffer.length}`);
    } else {
      if (room.browser && room.browser.readyState === WebSocket.OPEN) {
        console.log(`[relay] REJECT room_full sid=${ss} role=browser`);
        ws.close(4002, 'room_full'); return;
      }
      if (room._browserReconnectTimer) { clearTimeout(room._browserReconnectTimer); room._browserReconnectTimer = null; }
      room.browser = ws;
      console.log(`[relay] CONNECT sid=${ss} role=browser bufferLen=${room._buffer.length}`);
    }

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { console.log(`[relay] BAD_JSON sid=${ss} role=${role}`); return; }

      if (msg.type === 'join') {
        console.log(`[relay] JOIN sid=${ss} role=${role}`);
        ws.send(JSON.stringify({ type: 'joined', role }));
        if (!ws._joinFlushed) {
          ws._joinFlushed = true;
          const buffered = room._buffer;
          console.log(`[relay] FLUSH sid=${ss} role=${role} buffered=${buffered.length}`);
          for (const raw of buffered) {
            const m = JSON.parse(raw);
            console.log(`[relay] FLUSH_MSG sid=${ss} to=${role} type=${m.type}`);
            if (ws.readyState === 1) ws.send(raw);
          }
        }
        return;
      }

      if (msg.type === 'offer' || msg.type === 'candidate') {
        const target = role === 'pc' ? room.browser : room.pc;
        const targetRole = role === 'pc' ? 'browser' : 'pc';
        if (target?.readyState === 1) {
          console.log(`[relay] FORWARD sid=${ss} ${role}->${targetRole} type=${msg.type}`);
          target.send(raw.toString());
        } else {
          console.log(`[relay] BUFFER sid=${ss} ${role}->${targetRole} type=${msg.type} (target not connected)`);
          room._buffer.push(raw.toString());
        }
        return;
      }

      if (msg.type === 'answer') {
        if (room.pc?.readyState === 1) {
          console.log(`[relay] FORWARD sid=${ss} ${role}->pc type=answer`);
          room.pc.send(raw.toString());
        } else {
          console.log(`[relay] DROP sid=${ss} ${role}->pc type=answer (pc not connected)`);
        }
        return;
      }


    });

    ws.on('close', () => {
      if (role === 'pc') {
        room.pc = null;
        room._pcReconnectTimer = setTimeout(() => {
          room._pcReconnectTimer = null;
          if (!room.pc && room.browser?.readyState === 1) {
            room.browser.send(JSON.stringify({ type: 'peer_left' }));
          }
          if (!room.pc && !room.browser) { room._buffer = []; rooms.delete(sid); }
        }, reconnectGraceMs);
      } else {
        room.browser = null;
        room._browserReconnectTimer = setTimeout(() => {
          room._browserReconnectTimer = null;
          if (!room.browser && room.pc?.readyState === 1) {
            room.pc.send(JSON.stringify({ type: 'peer_left' }));
          }
          if (!room.pc && !room.browser) { room._buffer = []; rooms.delete(sid); }
        }, reconnectGraceMs);
      }
    });
  });

  return new Promise((resolve) => {
    server.listen(port, () => {
      console.log(`Relay listening on port ${port}`);
      resolve({
        server,
        close: () => new Promise((r) => server.close(r)),
      });
    });
  });
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const port = parseInt(process.env.RELAY_PORT ?? '3400', 10);
  createRelay(port);
}
