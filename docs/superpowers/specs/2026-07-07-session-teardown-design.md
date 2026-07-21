# Session Teardown — Design

**Date**: 2026-07-07
**Scope**: WebRTC instant-share session teardown (relay + browser + PC)

## Problem

1. Browser sends a `leave` WebSocket message before closing; PC does not. The `leave` handler on the relay only nulls the peer slot — the actual `peer_left` notification comes from `ws.on('close')`. So `leave` is redundant.
2. Browser's handling of `peer_left` (relay notification that the other side disconnected) is incomplete: it sets React state to `'closed'` but never closes the WS, data channel, or peer connection — leaking resources until component unmount.
3. The `bye` data-channel message is defined in the protocol but never sent. When transfer completes, both sides keep connections open indefinitely instead of tearing down.

## Design

### 1. Relay (`relay.mjs`)

**Remove** the `leave` message handler (lines 93-97). `reconnectGraceMs` and timer logic stay as-is — the relay cannot distinguish intentional vs. unintentional disconnects; a few extra seconds before cleanup is acceptable for both cases.

No other changes. The `ws.on('close')` handler is already correct.

### 2. Signal Channel (`web/instant-share/src/hooks/useSignalChannel.ts`)

**Remove** `leave` send from `close()`:

```ts
// Before:
try { wsRef.current?.send(JSON.stringify({ type: 'leave' })); } catch {}
wsRef.current?.close();

// After:
wsRef.current?.close();
```

**Add** a `closedByUser` ref to prevent the `ws.onclose` handler from emitting `peer_left` when we initiated the close ourselves:

```ts
const closedByUser = useRef(false);

// In close():
closedByUser.current = true;

// In ws.onclose:
if (!closedByUser.current) {
  emit({ type: 'peer_left' });
}
```

This is needed because when the browser receives `peer_left` from the relay and calls `signal.close()`, the resulting `ws.onclose` must not re-emit `peer_left` (avoiding double-processing).

`onmessage` handling of `peer_left` from the relay is unchanged — it emits the event.

### 3. WebRTC Hook (`web/instant-share/src/hooks/useWebRTC.ts`)

**Change** `peer_left` / `room_full` handler to do full cleanup:

```ts
} else if (e.type === 'peer_left' || e.type === 'room_full') {
  log.warn('useWebRTC: peer left or room full, closing all', e.type);
  try { channelRef.current?.close(); } catch {}
  try { pcRef.current?.close(); } catch {}
  pcRef.current = null;
  channelRef.current = null;
  signal.close();
  setState('closed');
}
```

The explicit `close()` callback is unchanged (already closes dc → pc → signal). The useEffect cleanup on unmount is unchanged (closes dc → pc, no signal since signal has its own lifecycle).

### 4. Transfer Hook (`web/instant-share/src/hooks/useTransfer.ts`)

**Add** `bye` send on transfer completion. In `downloadNext()`, the `idx >= pending.length` branch:

```ts
if (idx >= pending.length) {
  log.info('useTransfer: all downloads complete, sending bye');
  sendControl({ msg: 'bye' });
  setStatus('done');
  webrtc.close();
  return;
}
```

Sending `bye` via the data channel tells the PC to tear down cleanly. Then `webrtc.close()` closes dc → pc → signal on the browser side.

### 5. PC Peer (`dt_image_search/instant_sharing/webrtc_peer.py`)

No changes. Both teardown paths are already implemented:

- **`bye` received** (line 190-194): closes relay ws → falls through to `finally: _cleanup()` → closes dc + pc.
- **`peer_left` received** (line 159-161): `break` from relay message loop → `finally: _cleanup()`.

### 6. Mock PC Peer & Tests

- `mock-pc-peer.mjs`: no changes (already handles `peer_left` with `process.exit(0)`).
- `relay.test.mjs`: no changes (already passes `reconnectGraceMs: 0` for fast tests; `leave` is not tested).

## Teardown Sequences

### Normal completion (browser finishes all downloads)

```
Browser: downloadNext() detects completion
        → sendControl({ msg: 'bye' }) via dc
        → webrtc.close()
            → closes dc
            → closes pc
            → signal.close() → closes ws
PC:     receives 'bye' via dc
        → closes relay ws (async with context exits)
        → _cleanup() closes dc + pc
Relay:  browser ws.on('close') → reconnectGraceMs timer → peer_left to PC (redundant, PC already gone)
```

### Unexpected disconnect (either side)

```
Side A: ws closes (crash / network / app quit)
Relay:  ws.on('close') → reconnectGraceMs timer →
        if not reconnected: send peer_left to Side B
Side B: receives peer_left via ws message
        → closes dc, pc, signal
        → state = 'closed'
```

## No Changes

- Protocol file (`lib/protocol.ts`): `bye` is already defined.
- Relay `reconnectGraceMs`: retained (3s default).
- `webrtc_peer.py`: already handles both `bye` and `peer_left` correctly.
