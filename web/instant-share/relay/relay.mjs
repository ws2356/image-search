import { WebSocketServer } from 'ws';
import { createServer } from 'http';

export function createRelay(port) {
  const rooms = new Map();

  function getRoom(sid) {
    if (!rooms.has(sid)) rooms.set(sid, { pc: null, browser: null });
    return rooms.get(sid);
  }

  const server = createServer();
  const wss = new WebSocketServer({ server });

  wss.on('connection', (ws, req) => {
    const url = new URL(req.url ?? '/', 'http://x');
    const sid = url.searchParams.get('sid');
    const role = url.searchParams.get('role');

    if (!sid || (role !== 'pc' && role !== 'browser')) {
      ws.close(4001, 'invalid params');
      return;
    }

    const room = getRoom(sid);

    if (role === 'pc') {
      if (room.pc) { ws.close(4002, 'room_full'); return; }
      room.pc = ws;
    } else {
      if (room.browser) { ws.close(4002, 'room_full'); return; }
      room.browser = ws;
    }

    ws.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }

      if (msg.type === 'join') {
        ws.send(JSON.stringify({ type: 'joined', role }));
        return;
      }

      if (msg.type === 'offer' || msg.type === 'candidate') {
        const target = role === 'pc' ? room.browser : room.pc;
        if (target?.readyState === 1) target.send(raw.toString());
        return;
      }

      if (msg.type === 'answer') {
        if (room.pc?.readyState === 1) room.pc.send(raw.toString());
        return;
      }

      if (msg.type === 'leave') {
        if (role === 'pc') room.pc = null;
        else room.browser = null;
      }
    });

    ws.on('close', () => {
      if (role === 'pc') {
        room.pc = null;
        if (room.browser?.readyState === 1) room.browser.send(JSON.stringify({ type: 'peer_left' }));
      } else {
        room.browser = null;
        if (room.pc?.readyState === 1) room.pc.send(JSON.stringify({ type: 'peer_left' }));
      }
      if (!room.pc && !room.browser) rooms.delete(sid);
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
