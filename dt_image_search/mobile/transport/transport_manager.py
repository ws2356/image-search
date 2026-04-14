from __future__ import annotations

from dt_image_search.mobile.transport.lan_http_adapter import (
    LanHttpEndpointInfo,
    LanHttpTransportAdapter,
)
from dt_image_search.mobile.transport.usb_ws_adapter import (
    UsbBootstrapConfig,
    UsbTunnelTarget,
    UsbTransportState,
    UsbWebSocketTransportAdapter,
)


class MobileTransportManager:
    def __init__(
        self,
        *,
        lan_transport: LanHttpTransportAdapter,
        usb_transport: UsbWebSocketTransportAdapter,
    ):
        self._lan_transport = lan_transport
        self._usb_transport = usb_transport

    def start_lan(self) -> LanHttpEndpointInfo:
        return self._lan_transport.start()

    def stop_all(self) -> None:
        self._usb_transport.stop()
        self._lan_transport.stop()

    def configure_usb_bootstrap(self, config: UsbBootstrapConfig) -> None:
        self._usb_transport.configure_bootstrap(config)

    def start_usb(self) -> UsbTransportState:
        self._usb_transport.start()
        return self._usb_transport.state

    def stop_usb(self) -> None:
        self._usb_transport.stop()

    @property
    def usb_state(self) -> UsbTransportState:
        return self._usb_transport.state

    @property
    def usb_bootstrap_config(self) -> UsbBootstrapConfig | None:
        return self._usb_transport.bootstrap_config

    @property
    def usb_active_tunnel_target(self) -> UsbTunnelTarget | None:
        return self._usb_transport.active_tunnel_target

    @property
    def usb_last_probe_error(self) -> str | None:
        return self._usb_transport.last_probe_error
