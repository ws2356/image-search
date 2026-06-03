from __future__ import annotations

import logging
import socket
import threading
import time
from pathlib import Path
from typing import Callable, Mapping

from dt_image_search.instant_sharing.mdns import (
    ConnectionConfig,
    DeviceNameAdvertisement,
    DeviceSignatureAdvertisement,
    InstantShareBleDaemon,
    InstantShareBleService,
    InstantShareMDNSAdvertiser,
)
from dt_image_search.instant_sharing.https_bootstrap import InstantShareBootstrapServer
from dt_image_search.instant_sharing.contracts import TrustMode
from dt_image_search.instant_sharing.delivery import ClipboardWriter, InstantShareDeliveryService, QtClipboardWriter
from dt_image_search.instant_sharing.http_client import InstantShareHttpClient
from dt_image_search.instant_sharing.orchestrator import InstantShareReceiverOrchestrator, TrustHandshakeRequest
from dt_image_search.instant_sharing.sender_validation import SenderIdentity
from dt_image_search.instant_sharing.security import X25519TrustSessionKeyResolver
from dt_image_search.instant_sharing.trust_crypto import AesGcmTrustSessionProtector
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
    ) -> None:
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
        self._orchestrator = (
            orchestrator
            if orchestrator is not None
            else InstantShareReceiverOrchestrator(
                session_registry=self._session_registry,
                delivery_service=self._delivery_service,
            )
        )
        device_id = self._device_id_provider()
        desktop_name = self._desktop_name_provider()
        self._ble_service = InstantShareBleService(
            device_name_provider=self._device_name_advertisement,
            signature_provider=self._real_signature_provider,
            bootstrap_handler=self._handle_connection_config,
        )
        self._mdns_advertiser = InstantShareMDNSAdvertiser(
            ble_service=self._ble_service,
            device_id=device_id,
            desktop_name=desktop_name,
        )
        self._bootstrap_server = InstantShareBootstrapServer(
            ble_service=self._ble_service,
        )
        self._ble_daemon = InstantShareBleDaemon(
            ble_service=self._ble_service,
            is_enabled=self._is_enabled,
            heartbeat=heartbeat,
            poll_interval_seconds=poll_interval_seconds,
            mdns_advertiser=self._mdns_advertiser,
        )

    @property
    def ble_service(self) -> InstantShareBleService:
        return self._ble_service

    @property
    def mdns_advertiser(self) -> InstantShareMDNSAdvertiser:
        return self._mdns_advertiser

    @property
    def bootstrap_server(self) -> InstantShareBootstrapServer:
        return self._bootstrap_server

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
    def sender_identity(self) -> SenderIdentity:
        return self._sender_identity

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
        result = self._ble_daemon.start()
        if not result:
            _logger.error("[InstantShareRuntime] mDNS daemon failed to start")
            return False
        _logger.info(
            "[InstantShareRuntime] mDNS daemon started, is_advertising=%s, last_error=%s",
            self._mdns_advertiser.is_advertising,
            self._mdns_advertiser.last_error,
        )
        bs_ok = self._bootstrap_server.start()
        _logger.info(
            "[InstantShareRuntime] bootstrap HTTP server started=%s",
            bs_ok,
        )
        return result

    def stop(self) -> None:
        _logger = logging.getLogger(__name__)
        _logger.info("[InstantShareRuntime] stop() called")
        self._bootstrap_server.stop()
        self._ble_daemon.stop()
        _logger.info("[InstantShareRuntime] stop() complete")

    def bootstrap_connection_config(self, payload: Mapping[str, object] | ConnectionConfig) -> InstantShareSession:
        if isinstance(payload, ConnectionConfig):
            connection_config = payload
            self._handle_connection_config(connection_config)
        else:
            connection_config = ConnectionConfig.from_dict(payload)
            self._ble_service.handle_bootstrap(connection_config)
        return self._session_registry.require_session(connection_config.session_id)

    def create_http_client(self, connection_config: ConnectionConfig) -> tuple[InstantShareHttpClient, X25519TrustSessionKeyResolver, dict[str, object]]:
        key_resolver = X25519TrustSessionKeyResolver()
        trust_session_protector = AesGcmTrustSessionProtector(session_key_resolver=key_resolver)
        handshake_payload = key_resolver.handshake_request_payload()
        return InstantShareHttpClient(
            connection_config=connection_config,
            device_id=self._device_id_provider(),
            session_signer=self._sender_identity.session_signer,
            trust_session_protector=trust_session_protector,
        ), key_resolver, handshake_payload

    def run_receive_flow(self, connection_config: ConnectionConfig) -> object:
        session = self._session_registry.require_session(connection_config.session_id)
        client, key_resolver, handshake_payload = self.create_http_client(connection_config)
        correlation_id = connection_config.correlation_id

        if connection_config.metadata.trust_mode is TrustMode.FIRST_SHARE:
            self._orchestrator.complete_trust(
                session_id=connection_config.session_id,
                client=client,
                request=TrustHandshakeRequest(
                    pc_dh_public_key=str(handshake_payload.get("pc_dh_public_key", "")),
                    pc_nonce=str(handshake_payload.get("pc_nonce", "")),
                    pc_public_key_pem=self._sender_identity.public_key_pem(),
                ),
                correlation_id=correlation_id,
            )

        return self._orchestrator.receive_payload(
            session_id=connection_config.session_id,
            client=client,
            correlation_id=correlation_id,
        )

    def _handle_connection_config(self, connection_config: ConnectionConfig) -> None:
        self._orchestrator.handle_connection_config(connection_config)
        if self._auto_receive:
            logging.getLogger(__name__).info(
                "[InstantShareRuntime] auto_receive: starting receive flow in background thread"
            )
            threading.Thread(
                target=lambda: self._run_receive_flow_safely(connection_config),
                name="instant_share_auto_receive",
                daemon=True,
            ).start()

    def _run_receive_flow_safely(self, connection_config: ConnectionConfig) -> None:
        try:
            self.run_receive_flow(connection_config)
        except Exception:
            logging.getLogger(__name__).exception("[InstantShareRuntime] auto_receive failed")

    def _device_name_advertisement(self) -> DeviceNameAdvertisement:
        return DeviceNameAdvertisement(
            device_name=self._desktop_name_provider(),
            receiver_id=self._device_id_provider(),
        )

    def _real_signature_provider(self) -> DeviceSignatureAdvertisement:
        return self._sender_identity.device_signature_advertisement()

    def _create_default_sender_identity(self, config_dir: Path | None) -> SenderIdentity:
        identity_dir = config_dir or Path.home() / ".config" / "ausearch"
        return SenderIdentity.from_config_dir(identity_dir, device_id=self._device_id_provider())


def _default_desktop_name() -> str:
    hostname = socket.gethostname().strip()
    if hostname.lower().endswith(".local"):
        return hostname[:-6]
    return hostname or "Desktop"
