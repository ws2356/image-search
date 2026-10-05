# WebSocket event broker for the index server.
# sync → async 桥接的唯一写法:broadcast_threadsafe 经 asyncio.run_coroutine_threadsafe
# 投递到 uvicorn 主 loop(见 2026-10-04-asyncio-migration-notes.md)。
import asyncio
import json
import secrets
import threading

from starlette.websockets import WebSocketDisconnect


class EventBroker:
    """Manages authenticated WebSocket clients and fans out JSON payloads."""

    def __init__(self, token: str):
        self._token = token
        self._loop: asyncio.AbstractEventLoop | None = None
        self._clients = set()
        self._clients_lock = threading.Lock()

    def attach_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop

    async def connect(self, websocket) -> None:
        auth = websocket.query_params.get("auth")
        if not auth or not secrets.compare_digest(auth, self._token):
            await websocket.close(code=1008)
            return
        await websocket.accept()
        with self._clients_lock:
            self._clients.add(websocket)
        try:
            # Block until the client disconnects; the handler's lifetime is
            # the connection's lifetime.
            await websocket.receive_text()
        except WebSocketDisconnect:
            pass
        finally:
            with self._clients_lock:
                self._clients.discard(websocket)

    def broadcast_threadsafe(self, payload: dict) -> None:
        """Called from arbitrary (non-loop) threads; no-op before startup."""
        if self._loop is None:
            return
        asyncio.run_coroutine_threadsafe(self._broadcast(payload), self._loop)

    async def _broadcast(self, payload: dict) -> None:
        data = json.dumps(payload)
        with self._clients_lock:
            targets = list(self._clients)
        for ws in targets:
            try:
                await ws.send_text(data)
            except Exception:
                with self._clients_lock:
                    self._clients.discard(ws)
