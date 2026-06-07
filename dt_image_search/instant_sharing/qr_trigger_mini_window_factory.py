from __future__ import annotations

import logging
import socket
from typing import Any

from PySide6.QtCore import QTimer

from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler, StashEntry
from dt_image_search.instant_sharing.qr_trigger_mini_window import QRTriggerMiniWindow
from dt_image_search.tools.dts_dispatcher import dispatcher

_logger = logging.getLogger(__name__)


class QRTriggerMiniWindowFactory:
    def __init__(
        self,
        handler: QRTriggerHandler,
        *,
        pc_name: str = "",
        pc_port: int = 9527,
    ) -> None:
        self._handler = handler
        self._pc_name = pc_name or socket.gethostname()
        self._pc_port = pc_port
        self._windows: dict[str, QRTriggerMiniWindow] = {}
        self._stash_created_sub: Any = None
        self._stash_claimed_sub: Any = None
        self._stash_expired_sub: Any = None

    def start(self) -> None:
        if self._stash_created_sub is not None:
            return
        self._stash_created_sub = self._handler._on_stash_created
        self._stash_claimed_sub = self._handler._on_stash_claimed
        self._stash_expired_sub = self._handler._on_stash_expired
        self._handler._on_stash_created = self._on_stash_created
        self._handler._on_stash_claimed = self._on_stash_claimed
        self._handler._on_stash_expired = self._on_stash_expired
        _logger.info("[QRTriggerMiniWindowFactory] started")

    def stop(self) -> None:
        self._handler._on_stash_created = self._stash_created_sub
        self._handler._on_stash_claimed = self._stash_claimed_sub
        self._handler._on_stash_expired = self._stash_expired_sub
        self._stash_created_sub = None
        self._stash_claimed_sub = None
        self._stash_expired_sub = None
        for window in list(self._windows.values()):
            try:
                window.close()
            except RuntimeError:
                pass
        self._windows.clear()
        _logger.info("[QRTriggerMiniWindowFactory] stopped")

    def _on_stash_created(self, stash: StashEntry) -> None:
        QTimer.singleShot(0, lambda: self._show_window(stash))

    def _on_stash_claimed(self, stash_id: str) -> None:
        QTimer.singleShot(0, lambda: self._mark_claimed(stash_id))

    def _on_stash_expired(self, stash_id: str) -> None:
        QTimer.singleShot(0, lambda: self._mark_expired(stash_id))

    def _show_window(self, stash: StashEntry) -> None:
        window = QRTriggerMiniWindow(
            stash,
            pc_name=self._pc_name,
            pc_port=self._pc_port,
            on_cancel=self._on_cancel,
        )
        window.show_qr()
        window.show()
        self._windows[stash.stash_id] = window
        _logger.info(
            "[QRTriggerMiniWindowFactory] window shown: stash=%s type=%s",
            stash.stash_id,
            stash.content_type,
        )

    def _on_cancel(self, stash_id: str) -> None:
        self._handler.cancel_stash(stash_id)
        self._windows.pop(stash_id, None)

    def _mark_claimed(self, stash_id: str) -> None:
        window = self._windows.pop(stash_id, None)
        if window is not None:
            window.on_claimed()

    def _mark_expired(self, stash_id: str) -> None:
        window = self._windows.pop(stash_id, None)
        if window is not None:
            window.on_expired()
