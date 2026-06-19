from __future__ import annotations

import logging
import socket
import threading
import time
from pathlib import Path
from typing import Callable, Mapping

from dt_image_search.identity import initialize_device_identity
from dt_image_search.instant_sharing.mdns import (
    ConnectionConfig,
    DeviceNameAdvertisement,
    InstantShareBleDaemon,
    InstantShareBleService,
    InstantShareMDNSAdvertiser,
)
from dt_image_search.instant_sharing.https_bootstrap import InstantShareHTTPServer
from dt_image_search.instant_sharing.https_tls_server import InstantShareTLSServer
from dt_image_search.instant_sharing.contracts import TrustMode
from dt_image_search.instant_sharing.delivery import ClipboardWriter, InstantShareDeliveryService, QtClipboardWriter
from dt_image_search.instant_sharing.orchestrator import InstantShareReceiverOrchestrator
from dt_image_search.instant_sharing.qr_trigger_handler import QRTriggerHandler
from dt_image_search.instant_sharing.qr_trigger_mini_window_factory import QRTriggerMiniWindowFactory
from dt_image_search.instant_sharing.sender_validation import SenderIdentity
from dt_image_search.instant_sharing.session import InstantShareSession, InstantShareSessionRegistry
from dt_image_search.instant_sharing.trust_server import TrustSessionRegistry
from dt_image_search.instant_sharing.transfer_server import TransferHandler
from dt_image_search.instant_sharing.unix_socket_server import UnixSocketHttpServer
from dt_image_search.model.dt_device_id import get_device_id
from dt_image_search.model.feature_flags import is_instant_share_enabled


class InstantShareRuntime:
    def __init__(
        self,
        *,
        is_enabled: Callable[[], bool] = is_instant_share_enabled,
        device_id_provider: Callable[[], str] = get_device_id,
        desktop_name_provider: Callable[[], str] | None = None,
        sender_identity: SenderIdentity | None = None,
        config_dir: Path | None = None,
        clipboard_writer: ClipboardWriter | None = None,
        image_delivery_mode: str = "file",
        downloads_dir: Path | None = None,
        heartbeat: Callable[[], None] | None = None,
        poll_interval_seconds: float = 0.1,
        session_registry: InstantShareSessionRegistry | None = None,
        delivery_service: InstantShareDeliveryService | None = None,
        orchestrator: InstantShareReceiverOrchestrator | None = None,
        auto_receive: bool = False,
        trust_session_registry: TrustSessionRegistry | None = None,
        pin_display_callback: Callable[[str, str], None] | None = None,
        qr_window_factory: QRTriggerMiniWindowFactory | None = None,
    ) -> None:
        initialize_device_identity()

        self._auto_receive = auto_receive
        self._is_enabled = is_enabled
        self._device_id_provider = device_id_provider
        self._desktop_name_provider = desktop_name_provider or _default_desktop_name
        self._sender_identity = sender_identity or self._create_default_sender_identity(config_dir)
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
        self._trust_session_registry = trust_session_registry if trust_session_registry is not None else TrustSessionRegistry()
        self._transfer_handler = TransferHandler(
            session_registry=self._session_registry,
            delivery_service=self._delivery_service,
        )
        self._orchestrator = (
            orchestrator
            if orchestrator is not None
            else InstantShareReceiverOrchestrator(
                session_registry=self._session_registry,
                delivery_service=self._delivery_service,
                trust_session_registry=self._trust_session_registry,
            )
        )
        self._pin_display_callback = pin_display_callback
        desktop_name = self._desktop_name_provider()
        self._ble_service = InstantShareBleService(
            device_name_provider=self._device_name_advertisement,
            bootstrap_handler=self._handle_connection_config,
        )
        self._mdns_advertiser = InstantShareMDNSAdvertiser(
            ble_service=self._ble_service,
            desktop_name=desktop_name,
            port=0,
            tls_port=0,
        )
        self._qr_trigger_handler = QRTriggerHandler(
            trust_session_registry=self._trust_session_registry,
        )
        self._qr_window_factory = qr_window_factory
        self._unix_socket_server = UnixSocketHttpServer(
            request_handler=self._qr_trigger_handler.handle_trigger,
        )
        self._tls_server = InstantShareTLSServer(
            port=0,
            trust_session_registry=self._trust_session_registry,
            session_registry=self._session_registry,
            orchestrator=self._orchestrator,
            transfer_handler=self._transfer_handler,
            pin_display_callback=self._pin_display_callback,
            qr_trigger_handler=self._qr_trigger_handler,
        )
        self._http_server = InstantShareHTTPServer(
            port=0,
            trust_session_registry=self._trust_session_registry,
            session_registry=self._session_registry,
            orchestrator=self._orchestrator,
            transfer_handler=self._transfer_handler,
            pin_display_callback=self._pin_display_callback,
            qr_trigger_handler=self._qr_trigger_handler,
            tls_server=self._tls_server,
        )
        self._ble_daemon = InstantShareBleDaemon(
            ble_service=self._ble_service,
            is_enabled=self._is_enabled,
            heartbeat=heartbeat,
            poll_interval_seconds=poll_interval_seconds,
            mdns_advertiser=self._mdns_advertiser,
        )

    @property
    def device_id(self) -> str:
        return self._device_id_provider()

    @property
    def ble_service(self) -> InstantShareBleService:
        return self._ble_service

    @property
    def mdns_advertiser(self) -> InstantShareMDNSAdvertiser:
        return self._mdns_advertiser



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
    def trust_session_registry(self) -> TrustSessionRegistry:
        return self._trust_session_registry

    @property
    def sender_identity(self) -> SenderIdentity:
        return self._sender_identity

    @property
    def qr_trigger_handler(self) -> QRTriggerHandler:
        return self._qr_trigger_handler

    @property
    def qr_window_factory(self) -> QRTriggerMiniWindowFactory | None:
        return self._qr_window_factory

    @property
    def unix_socket_server(self) -> UnixSocketHttpServer:
        return self._unix_socket_server

    @property
    def http_server(self) -> InstantShareHTTPServer:
        return self._http_server

    @property
    def tls_server(self) -> InstantShareTLSServer:
        return self._tls_server

    @property
    def is_running(self) -> bool:
        return self._ble_daemon.is_running

    def start(self) -> bool:
        _logger = logging.getLogger(__name__)
        is_enabled_val = self._is_enabled()
        _logger.info(
            "[InstantShareRuntime] start() called, is_enabled=%s",
            is_enabled_val,
        )
        if not is_enabled_val:
            _logger.warning("[InstantShareRuntime] feature flag disabled, refusing to start")
        http_ok = self._http_server.start()
        _logger.info(
            "[InstantShareRuntime] instant-share HTTP server started=%s (port=%d)",
            http_ok,
            self._http_server.port,
        )
        tls_ok = self._tls_server.start()
        _logger.info(
            "[InstantShareRuntime] instant-share TLS server started=%s (port=%d)",
            tls_ok,
            self._tls_server.port,
        )
        self._mdns_advertiser._port = self._http_server.port
        self._mdns_advertiser._tls_port = self._tls_server.port
        result = self._ble_daemon.start()
        if not result:
            _logger.error("[InstantShareRuntime] mDNS daemon failed to start")
            return False
        _logger.info(
            "[InstantShareRuntime] mDNS daemon started, is_advertising=%s, last_error=%s",
            self._mdns_advertiser.is_advertising,
            self._mdns_advertiser.last_error,
        )
        unix_ok = self._unix_socket_server.start()
        _logger.info(
            "[InstantShareRuntime] QR Unix socket server started=%s (path=%s)",
            unix_ok,
            self._unix_socket_server.socket_path,
        )
        if self._qr_window_factory is not None:
            self._qr_window_factory.start()
            _logger.info("[InstantShareRuntime] QR window factory started")
        return result

    def stop(self) -> None:
        _logger = logging.getLogger(__name__)
        _logger.info("[InstantShareRuntime] stop() called")
        self._unix_socket_server.stop()
        self._tls_server.stop()
        self._http_server.stop()
        self._ble_daemon.stop()
        if self._qr_window_factory is not None:
            self._qr_window_factory.stop()
            _logger.info("[InstantShareRuntime] QR window factory stopped")
        _logger.info("[InstantShareRuntime] stop() complete")

    def bootstrap_connection_config(self, payload: Mapping[str, object] | ConnectionConfig) -> InstantShareSession:
        if isinstance(payload, ConnectionConfig):
            connection_config = payload
            self._handle_connection_config(connection_config)
        else:
            connection_config = ConnectionConfig.from_dict(payload)
            self._ble_service.handle_bootstrap(connection_config)
        return self._session_registry.get_session(connection_config.session_id)

    def _handle_connection_config(self, connection_config: ConnectionConfig) -> None:
        self._orchestrator.handle_connection_config(connection_config)
        if self._auto_receive:
            logging.getLogger(__name__).info(
                "[InstantShareRuntime] auto_receive: session ready, waiting for inbound trust+upload from mobile"
            )

    def _device_name_advertisement(self) -> DeviceNameAdvertisement:
        return DeviceNameAdvertisement(
            device_name=self._desktop_name_provider(),
            receiver_id=self._device_id_provider(),
        )

    def _create_default_sender_identity(self, config_dir: Path | None) -> SenderIdentity:
        identity_dir = config_dir or Path.home() / ".config" / "ausearch"
        return SenderIdentity.from_config_dir(identity_dir, device_id=self._device_id_provider())


def _default_desktop_name() -> str:
    hostname = socket.gethostname().strip()
    if hostname.lower().endswith(".local"):
        return hostname[:-6]
    return hostname or "Desktop"
