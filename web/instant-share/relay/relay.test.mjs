import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { createRelay } from './relay.mjs';

const PORT = 3401;
let relay;

before(async () => {
  relay = await createRelay(PORT, { reconnectGraceMs: 0 });
});

after(async () => {
  await relay.close();
});

function connect(sid, role) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}?sid=${sid}&role=${role}`);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
    setTimeout(() => reject(new Error('timeout')), 2000);
  });
}

function sendJson(ws, obj) {
  ws.send(JSON.stringify(obj));
}

function createMsgQueue(ws) {
  const pending = [];
  let waiter = null;

  function listener(d) {
    const parsed = typeof d === 'string' ? JSON.parse(d) : JSON.parse(d.toString());
    pending.push(parsed);
    if (waiter) {
      const w = waiter;
      waiter = null;
      w();
    }
  }
  ws.on('message', listener);

  return {
    next: () => new Promise((resolve, reject) => {
      if (pending.length > 0) {
        resolve(pending.shift());
        return;
      }
      waiter = () => resolve(pending.shift());
      setTimeout(() => { waiter = null; reject(new Error('timeout')); }, 2000);
    }),
    close: () => { ws.off('message', listener); waiter = null; },
  };
}

function nextMsg(ws) {
  return new Promise((resolve, reject) => {
    ws.once('message', (d) => resolve(JSON.parse(d.toString())));
    ws.once('error', reject);
    setTimeout(() => reject(new Error('timeout')), 2000);
  });
}

describe('relay', () => {
  it('rejects missing params', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
    const [code] = await new Promise((r) => ws.once('close', (c) => r([c])));
    assert.equal(code, 4001);
  });

  it('allows pc and browser to join a room', async () => {
    const pc = await connect('t1', 'pc');
    const browser = await connect('t1', 'browser');
    sendJson(pc, { type: 'join' });
    sendJson(browser, { type: 'join' });

    const pcMsg = await nextMsg(pc);
    const brMsg = await nextMsg(browser);
    assert.equal(pcMsg.type, 'joined');
    assert.equal(pcMsg.role, 'pc');
    assert.equal(brMsg.type, 'joined');
    assert.equal(brMsg.role, 'browser');
    pc.close();
    browser.close();
  });

  it('relays offer from pc to browser', async () => {
    const pc = await connect('t2', 'pc');
    const browser = await connect('t2', 'browser');
    sendJson(pc, { type: 'join' });
    sendJson(browser, { type: 'join' });
    await Promise.all([nextMsg(pc), nextMsg(browser)]);

    const promise = nextMsg(browser);
    sendJson(pc, { type: 'offer', sdp: 'v=0 mock' });
    const received = await promise;
    assert.equal(received.type, 'offer');
    assert.equal(received.sdp, 'v=0 mock');
    pc.close();
    browser.close();
  });

  it('relays answer from browser to pc', async () => {
    const pc = await connect('t3', 'pc');
    const browser = await connect('t3', 'browser');
    sendJson(pc, { type: 'join' });
    sendJson(browser, { type: 'join' });
    await Promise.all([nextMsg(pc), nextMsg(browser)]);

    const promise = nextMsg(pc);
    sendJson(browser, { type: 'answer', sdp: 'v=0 answer' });
    const received = await promise;
    assert.equal(received.type, 'answer');
    pc.close();
    browser.close();
  });

  it('rejects third connection (room_full)', async () => {
    const pc = await connect('t4', 'pc');
    const browser = await connect('t4', 'browser');

    const intruder = new WebSocket(`ws://127.0.0.1:${PORT}?sid=t4&role=browser`);
    const [code] = await new Promise((r) => intruder.once('close', (c) => r([c])));
    assert.equal(code, 4002);
    pc.close();
    browser.close();
  });

  it('buffers offer when peer not yet joined, flushes on join', async () => {
    const pc = await connect('t6', 'pc');
    sendJson(pc, { type: 'join' });
    await nextMsg(pc);

    sendJson(pc, { type: 'offer', sdp: 'v=0 early' });
    sendJson(pc, { type: 'candidate', candidate: { candidate: 'mock' } });

    const browser = await connect('t6', 'browser');
    const queue = createMsgQueue(browser);
    sendJson(browser, { type: 'join' });

    const m1 = await queue.next();
    const m2 = await queue.next();
    const m3 = await queue.next();

    assert.equal(m1.type, 'joined');
    assert.equal(m2.type, 'offer');
    assert.equal(m2.sdp, 'v=0 early');
    assert.equal(m3.type, 'candidate');

    queue.close();
    pc.close();
    browser.close();
  });

  it('notifies peer_left on disconnect', async () => {
    const pc = await connect('t5', 'pc');
    const browser = await connect('t5', 'browser');

    const promise = nextMsg(browser);
    pc.close();
    const msg = await promise;
    assert.equal(msg.type, 'peer_left');
    browser.close();
  });
});
