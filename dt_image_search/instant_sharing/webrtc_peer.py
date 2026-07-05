from __future__ import annotations

import asyncio
import json
import logging
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

RELAY_URL = "wss://dl.boldman.net/relay"
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
        _logger.info("[WebRTCPeer] starting session=%s stash=%s", self._session_id, self._stash.stash_id)
        try:
            import websockets

            async with websockets.connect(f"{self._relay_url}?sid={self._session_id}&role=pc") as ws:
                self._relay_ws = ws
                await ws.send(json.dumps({"type": "join"}))
                msg = json.loads(await ws.recv())
                if msg.get("type") != "joined":
                    _logger.warning("[WebRTCPeer] unexpected join response: %s", msg)
                    return

                self._pc = RTCPeerConnection()
                self._dc = self._pc.createDataChannel("share", ordered=True)
                self._dc.on("open", self._on_dc_open)
                self._dc.on("message", self._on_dc_message)

                @self._pc.on("iceconnectionstatechange")
                def _on_ice() -> None:
                    _logger.info("[WebRTCPeer] ice state: %s", self._pc.iceConnectionState if self._pc else "gone")

                offer = await self._pc.createOffer()
                await self._pc.setLocalDescription(offer)

                await ws.send(json.dumps({
                    "type": "offer",
                    "sdp": self._pc.localDescription.sdp,
                }))

                async for raw in ws:
                    try:
                        data = json.loads(raw)
                    except json.JSONDecodeError:
                        continue
                    if data["type"] == "answer":
                        await self._pc.setRemoteDescription(
                            RTCSessionDescription(sdp=data["sdp"], type="answer"),
                        )
                    elif data["type"] == "candidate":
                        await self._pc.addIceCandidate(data["candidate"])
                    elif data["type"] == "peer_left":
                        break
        except Exception:
            _logger.exception("[WebRTCPeer] session failed")
        finally:
            self._cleanup()

    def _on_dc_open(self) -> None:
        _logger.info("[WebRTCPeer] data channel open")

    def _on_dc_message(self, msg: str | bytes) -> None:
        ctrl = _read_control_message(msg if isinstance(msg, (str, bytes)) else b"")
        if ctrl is None:
            return

        ctrl_type = ctrl.get("msg")
        _logger.info("[WebRTCPeer] dc msg: %s", ctrl_type)

        if ctrl_type == "auth":
            self._handle_auth(ctrl)
        elif ctrl_type == "manifest":
            self._handle_manifest()
        elif ctrl_type == "download":
            self._handle_download(ctrl)
        elif ctrl_type == "bye":
            self._done.set()

    def _handle_auth(self, msg: dict) -> None:
        opt_code = msg.get("opt_code", "")
        trust_session = self._trust_session_registry.get_session(self._session_id)
        if trust_session and trust_session.verify_opt(opt_code):
            self._authenticated = True
            stash_type = "file" if self._stash.files and any(f.file_path for f in self._stash.files) else "text"
            self._send_control({"msg": "auth_ok", "payload_type": stash_type})
            _logger.info("[WebRTCPeer] auth ok session=%s", self._session_id)
        else:
            self._send_control({"msg": "auth_error", "error": "Invalid opt code"})
            _logger.warning("[WebRTCPeer] auth failed session=%s", self._session_id)

    def _handle_manifest(self) -> None:
        if not self._authenticated:
            self._send_control({"msg": "error", "code": "auth_required", "message": "Authenticate first"})
            return
        result = self._qr_handler.retrieve_stash_content(self._stash.stash_id)
        if result.get("_status") != 200:
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
        self._send_control({"msg": "manifest", "files": files_out})

    def _handle_download(self, msg: dict) -> None:
        if not self._authenticated:
            self._send_control({"msg": "error", "code": "auth_required", "message": "Authenticate first"})
            return
        index = msg.get("index", 0)
        status, file_bytes, content_type, filename = self._qr_handler.retrieve_stash_file(
            self._stash.stash_id, index,
        )
        if status != 200:
            self._send_control({
                "msg": "error",
                "code": "download_failed",
                "message": f"Failed to retrieve file index {index}",
            })
            return
        total_chunks = _estimate_chunk_count(len(file_bytes))
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
            offset += len(chunk_data)
        self._send_control({
            "msg": "file_end",
            "index": index,
        })

    def _send_control(self, msg: dict) -> None:
        if self._dc and self._dc.readyState == "open":
            self._dc.send(_encode_control(msg))

    def _cleanup(self) -> None:
        try:
            if self._dc:
                self._dc.close()
        except Exception:
            pass
        try:
            if self._pc:
                asyncio.run_coroutine_threadsafe(self._pc.close(), self._loop)
        except Exception:
            pass
        self._done.set()

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
            return
        self._active = True
        self._original_on_stash_created = self._qr_handler._on_stash_created
        self._qr_handler._on_stash_created = self._on_stash_created

        if self._loop is None:
            try:
                self._loop = asyncio.get_running_loop()
            except RuntimeError:
                self._loop = asyncio.new_event_loop()
                t = threading.Thread(target=self._loop.run_forever, daemon=True, name="webrtc-loop")
                t.start()
        assert self._loop is not None
        _logger.info("[WebRTCPeerManager] started")

    def stop(self) -> None:
        if not self._active:
            return
        self._active = False
        self._qr_handler._on_stash_created = self._original_on_stash_created
        self._original_on_stash_created = None

        with self._lock:
            for peer in list(self._peers.values()):
                peer._cleanup()
            self._peers.clear()
        _logger.info("[WebRTCPeerManager] stopped")

    def _on_stash_created(self, stash: StashEntry) -> None:
        if self._original_on_stash_created:
            self._original_on_stash_created(stash)
        session_id = self._qr_handler.get_session_id_for_stash(stash.stash_id)
        if not session_id:
            _logger.warning("[WebRTCPeerManager] no session_id for stash %s", stash.stash_id)
            return
        _logger.info(
            "[WebRTCPeerManager] starting webrtc peer session=%s stash=%s",
            session_id, stash.stash_id,
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
        peer.start()
