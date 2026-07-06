from __future__ import annotations

import asyncio
import json
import logging
import os
import struct
import threading
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Callable
from uuid import uuid4

from aiortc import RTCDataChannel, RTCPeerConnection, RTCSessionDescription

from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler, StashEntry

if TYPE_CHECKING:
    from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry

_logger = logging.getLogger(__name__)

RELAY_URL = os.getenv("RELAY_URL") or "wss://dl.boldman.net/relay"
MAX_MESSAGE_SIZE = 16 * 1024  # 16KB chunks
AUTH_TIMEOUT_SECONDS = 15

CHUNK_HEADER_FMT = "!II"  # index (4B) + offset (4B) per chunk
CHUNK_HEADER_SIZE = struct.calcsize(CHUNK_HEADER_FMT)

CONTROL_TERMINATOR = b"\n\n"


@dataclass
class InFlightDownload:
    index: int
    stash_id: str
    content_type: str
    filename: str
    data: bytes = b""
    chunk_index: int = 0
    total_chunks: int = 0


def _encode_control(obj: dict) -> bytes:
    return json.dumps(obj).encode("utf-8") + CONTROL_TERMINATOR


def _read_control_message(msg: str | bytes) -> dict | None:
    text = msg.decode("utf-8") if isinstance(msg, bytes) else msg
    stripped = text.rstrip("\n")
    try:
        return json.loads(stripped)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def _estimate_chunk_count(size: int) -> int:
    if size <= MAX_MESSAGE_SIZE:
        return 1
    return (size + MAX_MESSAGE_SIZE - 1) // MAX_MESSAGE_SIZE


class WebRTCPeer:
    def __init__(
        self,
        *,
        session_id: str,
        stash: StashEntry,
        qr_handler: QRTriggerHandler,
        trust_session_registry: TrustSessionRegistry,
        loop: asyncio.AbstractEventLoop,
        relay_url: str = RELAY_URL,
    ) -> None:
        self._session_id = session_id
        self._stash = stash
        self._qr_handler = qr_handler
        self._trust_session_registry = trust_session_registry
        self._relay_url = relay_url
        self._loop = loop
        self._pc: RTCPeerConnection | None = None
        self._dc: RTCDataChannel | None = None
        self._relay_ws = None
        self._authenticated = False
        self._done = threading.Event()

    def start(self) -> None:
        asyncio.run_coroutine_threadsafe(self._run(), self._loop)

    async def _run(self) -> None:
        _logger.debug("[WebRTCPeer] relay url=%s", self._relay_url)
        _logger.info(
            "[WebRTCPeer] _run starting session=%s stash=%s relay=%s",
            self._session_id, self._stash.stash_id, self._relay_url,
        )
        try:
            import websockets

            relay_url = f"{self._relay_url}?sid={self._session_id}&role=pc"
            _logger.info("[WebRTCPeer] connecting to relay %s", relay_url)
            async with websockets.connect(relay_url) as ws:
                self._relay_ws = ws
                _logger.info("[WebRTCPeer] relay ws connected, sending join")
                await ws.send(json.dumps({"type": "join"}))
                msg = json.loads(await ws.recv())
                _logger.info("[WebRTCPeer] relay join response: %s", msg)
                if msg.get("type") != "joined":
                    _logger.warning("[WebRTCPeer] unexpected join response: %s", msg)
                    return

                _logger.info("[WebRTCPeer] creating RTCPeerConnection")
                self._pc = RTCPeerConnection()
                self._dc = self._pc.createDataChannel("share", ordered=True)
                self._dc.on("open", self._on_dc_open)
                self._dc.on("message", self._on_dc_message)

                @self._pc.on("iceconnectionstatechange")
                def _on_ice() -> None:
                    state = self._pc.iceConnectionState if self._pc else "gone"
                    _logger.info("[WebRTCPeer] ice connection state: %s (session=%s)", state, self._session_id)

                @self._pc.on("icegatheringstatechange")
                def _on_gather() -> None:
                    state = self._pc.iceGatheringState if self._pc else "gone"
                    _logger.info("[WebRTCPeer] ice gathering state: %s (session=%s)", state, self._session_id)

                @self._pc.on("connectionstatechange")
                def _on_conn() -> None:
                    state = self._pc.connectionState if self._pc else "gone"
                    _logger.info("[WebRTCPeer] pc connection state: %s (session=%s)", state, self._session_id)

                _logger.info("[WebRTCPeer] creating offer (session=%s)", self._session_id)
                offer = await self._pc.createOffer()
                _logger.info("[WebRTCPeer] setting local description (session=%s)", self._session_id)
                await self._pc.setLocalDescription(offer)

                _logger.info(
                    "[WebRTCPeer] sending offer to relay, sdp length=%d (session=%s)",
                    len(self._pc.localDescription.sdp), self._session_id,
                )
                await ws.send(json.dumps({
                    "type": "offer",
                    "sdp": self._pc.localDescription.sdp,
                }))
                _logger.info("[WebRTCPeer] offer sent, waiting for relay messages (session=%s)", self._session_id)

                async for raw in ws:
                    _logger.debug("[WebRTCPeer] relay recv: %s (session=%s)", raw[:200], self._session_id)
                    try:
                        data = json.loads(raw)
                    except json.JSONDecodeError:
                        _logger.warning("[WebRTCPeer] relay msg not json: %s", raw[:200])
                        continue
                    if data["type"] == "answer":
                        _logger.info("[WebRTCPeer] received answer from relay (session=%s)", self._session_id)
                        await self._pc.setRemoteDescription(
                            RTCSessionDescription(sdp=data["sdp"], type="answer"),
                        )
                        _logger.info("[WebRTCPeer] remote description set (session=%s)", self._session_id)
                    elif data["type"] == "candidate":
                        _logger.info("[WebRTCPeer] received ice candidate from relay (session=%s)", self._session_id)
                        await self._pc.addIceCandidate(data["candidate"])
                    elif data["type"] == "peer_left":
                        _logger.info("[WebRTCPeer] peer_left, breaking loop (session=%s)", self._session_id)
                        break
                    else:
                        _logger.debug("[WebRTCPeer] unknown relay msg type: %s (session=%s)", data.get("type"), self._session_id)
        except Exception as exc:
            _logger.exception("[WebRTCPeer] session failed (session=%s): %s", self._session_id, exc)
        finally:
            _logger.info("[WebRTCPeer] _run cleanup (session=%s)", self._session_id)
            self._cleanup()

    def _on_dc_open(self) -> None:
        _logger.info("[WebRTCPeer] data channel OPEN (session=%s)", self._session_id)

    def _on_dc_message(self, msg: str | bytes) -> None:
        raw = msg if isinstance(msg, (str, bytes)) else b""
        ctrl = _read_control_message(raw)
        if ctrl is None:
            _logger.debug("[WebRTCPeer] dc binary/unknown recv %dB (session=%s)", len(raw) if isinstance(raw, (bytes, str)) else 0, self._session_id)
            return

        ctrl_type = ctrl.get("msg")
        _logger.info("[WebRTCPeer] dc msg recv: %s (session=%s)", ctrl_type, self._session_id)

        if ctrl_type == "auth":
            self._handle_auth(ctrl)
        elif ctrl_type == "manifest":
            self._handle_manifest()
        elif ctrl_type == "download":
            self._handle_download(ctrl)
        elif ctrl_type == "bye":
            _logger.info("[WebRTCPeer] bye received, setting done (session=%s)", self._session_id)
            self._done.set()
        else:
            _logger.warning("[WebRTCPeer] unknown dc msg: %s (session=%s)", ctrl_type, self._session_id)

    def _handle_auth(self, msg: dict) -> None:
        opt_code = msg.get("opt_code", "")
        _logger.info("[WebRTCPeer] _handle_auth (session=%s)", self._session_id)
        trust_session = self._trust_session_registry.get_session(self._session_id)
        if trust_session is None:
            _logger.warning("[WebRTCPeer] no trust session found for session=%s", self._session_id)
        if trust_session and trust_session.verify_opt(opt_code):
            self._authenticated = True
            stash_type = "file" if self._stash.files and any(f.file_path for f in self._stash.files) else "text"
            _logger.info(
                "[WebRTCPeer] auth OK, sending auth_ok payload_type=%s (session=%s)",
                stash_type, self._session_id,
            )
            self._send_control({"msg": "auth_ok", "payload_type": stash_type})
        else:
            _logger.warning("[WebRTCPeer] auth FAILED, invalid opt_code (session=%s)", self._session_id)
            self._send_control({"msg": "auth_error", "error": "Invalid opt code"})

    def _handle_manifest(self) -> None:
        _logger.info("[WebRTCPeer] _handle_manifest (session=%s stash=%s)", self._session_id, self._stash.stash_id)
        if not self._authenticated:
            _logger.warning("[WebRTCPeer] manifest requested before auth (session=%s)", self._session_id)
            self._send_control({"msg": "error", "code": "auth_required", "message": "Authenticate first"})
            return
        result = self._qr_handler.retrieve_stash_content(self._stash.stash_id)
        status = result.get("_status")
        _logger.info(
            "[WebRTCPeer] retrieve_stash_content status=%s stash=%s (session=%s)",
            status, self._stash.stash_id, self._session_id,
        )
        if status != 200:
            _logger.warning("[WebRTCPeer] stash error: %s (session=%s)", result.get("error"), self._session_id)
            self._send_control({
                "msg": "error",
                "code": "stash_error",
                "message": result.get("error", "unknown"),
            })
            return
        raw_files = result.get("files", [])
        files_out = []
        for f in raw_files:
            entry = {
                "index": f.get("index", 0),
                "type": f.get("type", "file"),
                "content_type": f.get("content_type", "application/octet-stream"),
                "filename": f.get("filename", ""),
                "size_bytes": f.get("size_bytes", 0),
            }
            if f.get("content") is not None:
                entry["content"] = f["content"]
            if entry["type"] in ("text", "link", "html"):
                entry["size_bytes"] = len(f.get("content", ""))
            files_out.append(entry)
        _logger.info(
            "[WebRTCPeer] sending manifest files=%d (session=%s)",
            len(files_out), self._session_id,
        )
        self._send_control({"msg": "manifest", "files": files_out})

    def _handle_download(self, msg: dict) -> None:
        index = msg.get("index", 0)
        _logger.info("[WebRTCPeer] _handle_download index=%d (session=%s)", index, self._session_id)
        if not self._authenticated:
            _logger.warning("[WebRTCPeer] download before auth (session=%s)", self._session_id)
            self._send_control({"msg": "error", "code": "auth_required", "message": "Authenticate first"})
            return
        status, file_bytes, content_type, filename = self._qr_handler.retrieve_stash_file(
            self._stash.stash_id, index,
        )
        _logger.info(
            "[WebRTCPeer] retrieve_stash_file status=%s index=%d bytes=%d content_type=%s (session=%s)",
            status, index, len(file_bytes), content_type, self._session_id,
        )
        if status != 200:
            _logger.warning("[WebRTCPeer] download failed index=%d status=%d (session=%s)", index, status, self._session_id)
            self._send_control({
                "msg": "error",
                "code": "download_failed",
                "message": f"Failed to retrieve file index {index}",
            })
            return
        total_chunks = _estimate_chunk_count(len(file_bytes))
        _logger.info(
            "[WebRTCPeer] sending file_start index=%d size=%d chunks=%d (session=%s)",
            index, len(file_bytes), total_chunks, self._session_id,
        )
        self._send_control({
            "msg": "file_start",
            "index": index,
            "content_type": content_type,
            "filename": filename,
            "size": len(file_bytes),
            "chunks": total_chunks,
        })
        offset = 0
        for chunk_idx in range(total_chunks):
            chunk_data = file_bytes[offset:offset + MAX_MESSAGE_SIZE]
            header = struct.pack(CHUNK_HEADER_FMT, index, offset)
            if self._dc and self._dc.readyState == "open":
                self._dc.send(header + chunk_data)
            else:
                _logger.warning("[WebRTCPeer] dc not open during chunk send (session=%s)", self._session_id)
                break
            offset += len(chunk_data)
        _logger.info("[WebRTCPeer] sending file_end index=%d (session=%s)", index, self._session_id)
        self._send_control({
            "msg": "file_end",
            "index": index,
        })

    def _send_control(self, msg: dict) -> None:
        if self._dc and self._dc.readyState == "open":
            _logger.debug("[WebRTCPeer] sending control: %s (session=%s)", msg.get("msg"), self._session_id)
            self._dc.send(_encode_control(msg))
        else:
            _logger.warning("[WebRTCPeer] _send_control failed, dc not open: %s (session=%s)", msg.get("msg"), self._session_id)

    def _cleanup(self) -> None:
        _logger.info("[WebRTCPeer] _cleanup start (session=%s)", self._session_id)
        try:
            if self._dc:
                _logger.debug("[WebRTCPeer] closing dc (session=%s)", self._session_id)
                self._dc.close()
        except Exception:
            _logger.debug("[WebRTCPeer] dc close exception (session=%s)", self._session_id, exc_info=True)
        try:
            if self._pc:
                _logger.debug("[WebRTCPeer] closing pc (session=%s)", self._session_id)
                asyncio.run_coroutine_threadsafe(self._pc.close(), self._loop)
        except Exception:
            _logger.debug("[WebRTCPeer] pc close exception (session=%s)", self._session_id, exc_info=True)
        self._done.set()
        _logger.info("[WebRTCPeer] _cleanup done (session=%s)", self._session_id)

    def wait(self, timeout: float | None = None) -> bool:
        return self._done.wait(timeout)


class WebRTCPeerManager:
    def __init__(
        self,
        *,
        qr_handler: QRTriggerHandler,
        trust_session_registry: TrustSessionRegistry,
        loop: asyncio.AbstractEventLoop | None = None,
        relay_url: str = RELAY_URL,
    ) -> None:
        self._qr_handler = qr_handler
        self._trust_session_registry = trust_session_registry
        self._relay_url = relay_url
        self._loop: asyncio.AbstractEventLoop | None = loop
        self._peers: dict[str, WebRTCPeer] = {}
        self._original_on_stash_created: Callable | None = None
        self._active = False
        self._lock = threading.Lock()

    def start(self) -> None:
        if self._active:
            _logger.debug("[WebRTCPeerManager] already active")
            return
        self._active = True
        self._original_on_stash_created = self._qr_handler._on_stash_created
        self._qr_handler._on_stash_created = self._on_stash_created
        _logger.info("[WebRTCPeerManager] intercepting on_stash_created callback")

        if self._loop is None:
            try:
                self._loop = asyncio.get_running_loop()
                _logger.info("[WebRTCPeerManager] using existing event loop")
            except RuntimeError:
                self._loop = asyncio.new_event_loop()
                t = threading.Thread(target=self._loop.run_forever, daemon=True, name="webrtc-loop")
                t.start()
                _logger.info("[WebRTCPeerManager] created new event loop on thread 'webrtc-loop'")
        assert self._loop is not None
        _logger.info(
            "[WebRTCPeerManager] started, relay_url=%s, active_peers=%d",
            self._relay_url, len(self._peers),
        )

    def stop(self) -> None:
        if not self._active:
            _logger.debug("[WebRTCPeerManager] not active, stop noop")
            return
        self._active = False
        self._qr_handler._on_stash_created = self._original_on_stash_created
        self._original_on_stash_created = None
        _logger.info("[WebRTCPeerManager] stopped, cleaning up %d peers", len(self._peers))

        with self._lock:
            for sid, peer in list(self._peers.items()):
                _logger.info("[WebRTCPeerManager] cleaning up peer session=%s", sid)
                peer._cleanup()
            self._peers.clear()
        _logger.info("[WebRTCPeerManager] stop complete")

    def _on_stash_created(self, stash: StashEntry) -> None:
        _logger.info(
            "[WebRTCPeerManager] _on_stash_created stash=%s content_type=%s files=%d",
            stash.stash_id, stash.content_type, len(stash.files) if stash.files else 0,
        )
        if self._original_on_stash_created:
            _logger.debug("[WebRTCPeerManager] forwarding to original on_stash_created")
            self._original_on_stash_created(stash)
        session_id = self._qr_handler.get_session_id_for_stash(stash.stash_id)
        if not session_id:
            _logger.warning(
                "[WebRTCPeerManager] no session_id found for stash=%s — WebRTC peer NOT started",
                stash.stash_id,
            )
            return
        _logger.info(
            "[WebRTCPeerManager] starting WebRTCPeer session=%s stash=%s relay=%s",
            session_id, stash.stash_id, self._relay_url,
        )
        peer = WebRTCPeer(
            session_id=session_id,
            stash=stash,
            qr_handler=self._qr_handler,
            trust_session_registry=self._trust_session_registry,
            loop=self._loop,
            relay_url=self._relay_url,
        )
        with self._lock:
            self._peers[session_id] = peer
        _logger.info("[WebRTCPeerManager] peer registered, calling peer.start() session=%s", session_id)
        peer.start()
        _logger.info("[WebRTCPeerManager] peer.start() returned session=%s", session_id)
