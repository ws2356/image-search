from __future__ import annotations

import socket
import time
from pathlib import Path
from typing import Callable, Mapping

from dt_image_search.instant_sharing.ble import (
    CONNECTION_CONFIG_CHARACTERISTIC,
    ConnectionConfig,
    DeviceNameAdvertisement,
    DeviceSignatureAdvertisement,
    InstantShareBleDaemon,
    InstantShareBleService,
)
from dt_image_search.instant_sharing.delivery import ClipboardWriter, InstantShareDeliveryService, QtClipboardWriter
from dt_image_search.instant_sharing.orchestrator import InstantShareReceiverOrchestrator
from dt_image_search.instant_sharing.session import InstantShareSession, InstantShareSessionRegistry
from dt_image_search.model.dt_device_id import get_device_id
from dt_image_search.model.feature_flags import is_instant_share_enabled


class InstantShareRuntime:
    def __init__(
        self,
        *,
        is_enabled: Callable[[], bool] = is_instant_share_enabled,
        device_id_provider: Callable[[], str] = get_device_id,
        desktop_name_provider: Callable[[], str] | None = None,
        signature_provider: Callable[[], DeviceSignatureAdvertisement] | None = None,
        clipboard_writer: ClipboardWriter | None = None,
        image_delivery_mode: str = "file",
        downloads_dir: Path | None = None,
        heartbeat: Callable[[], None] | None = None,
        poll_interval_seconds: float = 0.1,
        session_registry: InstantShareSessionRegistry | None = None,
        delivery_service: InstantShareDeliveryService | None = None,
        orchestrator: InstantShareReceiverOrchestrator | None = None,
    ) -> None:
        self._is_enabled = is_enabled
        self._device_id_provider = device_id_provider
        self._desktop_name_provider = desktop_name_provider or _default_desktop_name
        self._signature_provider = signature_provider or self._default_signature_provider
        self._session_registry = session_registry if session_registry is not None else InstantShareSessionRegistry()
        self._delivery_service = (
            delivery_service
            if delivery_service is not None
            else InstantShareDeliveryService(
                clipboard_writer=clipboard_writer if clipboard_writer is not None else QtClipboardWriter(),
                image_delivery_mode=image_delivery_mode,
                downloads_dir=downloads_dir,
            )
        )
        self._orchestrator = (
            orchestrator
            if orchestrator is not None
            else InstantShareReceiverOrchestrator(
                session_registry=self._session_registry,
                delivery_service=self._delivery_service,
            )
        )
        self._ble_service = InstantShareBleService(
            device_name_provider=self._device_name_advertisement,
            signature_provider=self._signature_provider,
            bootstrap_handler=self._handle_connection_config,
        )
        self._ble_daemon = InstantShareBleDaemon(
            ble_service=self._ble_service,
            is_enabled=self._is_enabled,
            heartbeat=heartbeat,
            poll_interval_seconds=poll_interval_seconds,
        )

    @property
    def ble_service(self) -> InstantShareBleService:
        return self._ble_service

    @property
    def ble_daemon(self) -> InstantShareBleDaemon:
        return self._ble_daemon

    @property
    def session_registry(self) -> InstantShareSessionRegistry:
        return self._session_registry

    @property
    def delivery_service(self) -> InstantShareDeliveryService:
        return self._delivery_service

    @property
    def orchestrator(self) -> InstantShareReceiverOrchestrator:
        return self._orchestrator

    @property
    def is_running(self) -> bool:
        return self._ble_daemon.is_running

    def start(self) -> bool:
        return self._ble_daemon.start()

    def stop(self) -> None:
        self._ble_daemon.stop()

    def bootstrap_connection_config(self, payload: Mapping[str, object] | ConnectionConfig) -> InstantShareSession:
        if isinstance(payload, ConnectionConfig):
            connection_config = payload
            self._handle_connection_config(connection_config)
        else:
            connection_config = ConnectionConfig.from_dict(payload)
            self._ble_service.write_characteristic(CONNECTION_CONFIG_CHARACTERISTIC, payload)
        return self._session_registry.require_session(connection_config.session_id)

    def _handle_connection_config(self, connection_config: ConnectionConfig) -> None:
        self._orchestrator.handle_connection_config(connection_config)

    def _device_name_advertisement(self) -> DeviceNameAdvertisement:
        return DeviceNameAdvertisement(
            device_name=self._desktop_name_provider(),
            receiver_id=self._device_id_provider(),
        )

    def _default_signature_provider(self) -> DeviceSignatureAdvertisement:
        return DeviceSignatureAdvertisement(
            signature="instant-share-signature-pending",
            signature_key_id=self._device_id_provider(),
            timestamp_ms=int(time.time() * 1000),
        )


def _default_desktop_name() -> str:
    hostname = socket.gethostname().strip()
    if hostname.lower().endswith(".local"):
        return hostname[:-6]
    return hostname or "Desktop"