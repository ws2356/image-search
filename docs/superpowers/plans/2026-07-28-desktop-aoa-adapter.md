# Desktop AOA Adapter Implementation Plan


**Goal:** Implement the production desktop AOA adapter (`UsbAoaTransportAdapter`) that detects Android devices in AOA mode, authenticates them, and routes `dtis.mobile-transport.v1` envelopes through the existing `MobileTransportRouter`.

**Architecture:** A daemon probe thread lists USB devices with PyUSB, negotiates AOA accessory mode, opens bulk endpoints, runs the auth challenge, then reads/writes framed messages over the AOA bulk pipe. The adapter reuses the same envelope contracts, `TransferAssetUploadStream`, and `MobileTransportRouter` already used by the LAN and iOS USB transports.

**Tech Stack:** Python 3.10, PyUSB, `dt_image_search` transport contracts/router, `MobilePayloadEncryption`, pytest.

## Global Constraints

- Target Python 3.10.
- All USB transport code must reuse `dt_image_search.mobile.transport.contracts`, `router`, and `asset_upload_stream`.
- Use `pathlib.Path` for any paths.
- Use `dt_image_search.telemetry.telemetry_client.log` for logging; no `print()` calls.
- Use parameterized queries for any SQL; this layer does not touch the database directly.
- Tests are written with pytest and added to the existing test suite.
- macOS-first host validation; Windows driver work is documented and deferred.

---

## Task 1: AOA frame codec

**Files:**
- Create: `dt_image_search/mobile/transport/aoa_frame_codec.py`
- Test: `dt_image_search/tests/unit/transport/test_aoa_frame_codec.py`

**Interfaces:**
- Consumes: nothing (pure bytes).
- Produces: `encode_aoa_frame(request_id: str, payload: bytes, flags: int = AOA_FRAME_FLAG_TEXT) -> bytes`, `decode_aoa_frame(data: bytes) -> tuple[str, int, bytes]`, `AoaFrameDecoder` incremental parser.

- [ ] **Step 1: Write the failing test**

```python
def test_encode_and_decode_aoa_frame():
    from dt_image_search.mobile.transport.aoa_frame_codec import (
        AOA_FRAME_FLAG_BINARY,
        AOA_FRAME_FLAG_TEXT,
        encode_aoa_frame,
        decode_aoa_frame,
    )

    request_id = "12345678-1234-1234-1234-123456789012"
    payload = b"hello"

    text_frame = encode_aoa_frame(request_id, payload)
    assert len(text_frame) == 1 + 36 + 4 + 1 + 5
    decoded_request_id, decoded_flags, decoded_payload = decode_aoa_frame(text_frame)
    assert decoded_request_id == request_id
    assert decoded_flags == AOA_FRAME_FLAG_TEXT
    assert decoded_payload == payload

    binary_frame = encode_aoa_frame(request_id, payload, flags=AOA_FRAME_FLAG_BINARY)
    _, binary_flags, _ = decode_aoa_frame(binary_frame)
    assert binary_flags == AOA_FRAME_FLAG_BINARY
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `python -m pytest dt_image_search/tests/unit/transport/test_aoa_frame_codec.py -v`
Expected: `ModuleNotFoundError` or `ImportError` for `aoa_frame_codec`.

- [ ] **Step 3: Implement `aoa_frame_codec.py`**

```python
from __future__ import annotations

AOA_FRAME_VERSION = 1
AOA_REQUEST_ID_LENGTH = 36
AOA_FRAME_HEADER_LENGTH = 1 + AOA_REQUEST_ID_LENGTH + 4 + 1
AOA_FRAME_FLAG_TEXT = 0x00
AOA_FRAME_FLAG_BINARY = 0x01


class AoaFrameDecoder:
    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, data: bytes) -> list[tuple[str, int, bytes]]:
        self._buffer.extend(data)
        frames: list[tuple[str, int, bytes]] = []
        while True:
            if len(self._buffer) < AOA_FRAME_HEADER_LENGTH:
                break
            version = self._buffer[0]
            if version != AOA_FRAME_VERSION:
                raise ValueError(f"Unsupported AOA frame version: {version}")
            request_id_bytes = self._buffer[1 : 1 + AOA_REQUEST_ID_LENGTH]
            try:
                request_id = request_id_bytes.decode("ascii").strip()
            except UnicodeDecodeError as exc:
                raise ValueError("AOA frame request_id must be ASCII") from exc
            payload_length_start = 1 + AOA_REQUEST_ID_LENGTH
            payload_length_end = payload_length_start + 4
            payload_length = int.from_bytes(
                self._buffer[payload_length_start:payload_length_end],
                byteorder="big",
                signed=False,
            )
            flags_offset = payload_length_end
            flags = self._buffer[flags_offset]
            if flags not in (AOA_FRAME_FLAG_TEXT, AOA_FRAME_FLAG_BINARY):
                raise ValueError(f"Unsupported AOA frame flags: {flags}")
            frame_length = AOA_FRAME_HEADER_LENGTH + payload_length
            if len(self._buffer) < frame_length:
                break
            payload = self._buffer[AOA_FRAME_HEADER_LENGTH:frame_length]
            frames.append((request_id, flags, bytes(payload)))
            del self._buffer[:frame_length]
        return frames


def encode_aoa_frame(request_id: str, payload: bytes, flags: int = AOA_FRAME_FLAG_TEXT) -> bytes:
    request_id_bytes = request_id.encode("ascii")
    if len(request_id_bytes) != AOA_REQUEST_ID_LENGTH:
        raise ValueError(f"request_id must be exactly {AOA_REQUEST_ID_LENGTH} ASCII bytes")
    if flags not in (AOA_FRAME_FLAG_TEXT, AOA_FRAME_FLAG_BINARY):
        raise ValueError(f"Unsupported AOA frame flags: {flags}")
    header = bytearray()
    header.append(AOA_FRAME_VERSION)
    header.extend(request_id_bytes)
    header.extend(len(payload).to_bytes(4, byteorder="big", signed=False))
    header.append(flags)
    return bytes(header) + payload


def decode_aoa_frame(data: bytes) -> tuple[str, int, bytes]:
    if len(data) < AOA_FRAME_HEADER_LENGTH:
        raise ValueError("AOA frame is too short")
    version = data[0]
    if version != AOA_FRAME_VERSION:
        raise ValueError(f"Unsupported AOA frame version: {version}")
    request_id = data[1 : 1 + AOA_REQUEST_ID_LENGTH].decode("ascii").strip()
    payload_length_start = 1 + AOA_REQUEST_ID_LENGTH
    payload_length_end = payload_length_start + 4
    payload_length = int.from_bytes(
        data[payload_length_end - 4 : payload_length_end],
        byteorder="big",
        signed=False,
    )
    flags = data[payload_length_end]
    if flags not in (AOA_FRAME_FLAG_TEXT, AOA_FRAME_FLAG_BINARY):
        raise ValueError(f"Unsupported AOA frame flags: {flags}")
    frame_length = AOA_FRAME_HEADER_LENGTH + payload_length
    if len(data) < frame_length:
        raise ValueError("AOA frame payload is incomplete")
    payload = data[AOA_FRAME_HEADER_LENGTH:frame_length]
    if len(payload) != payload_length:
        raise ValueError("AOA frame payload length mismatch")
    return request_id, flags, payload
```

- [ ] **Step 4: Add incremental decoder tests**

```python
def test_decoder_recovers_from_partial_reads():
    from dt_image_search.mobile.transport.aoa_frame_codec import (
        AOA_FRAME_FLAG_TEXT,
        encode_aoa_frame,
        AoaFrameDecoder,
    )

    decoder = AoaFrameDecoder()
    frame = encode_aoa_frame("12345678-1234-1234-1234-123456789012", b"payload")
    assert decoder.feed(frame[:10]) == []
    assert decoder.feed(frame[10:25]) == []
    assert decoder.feed(frame[25:]) == [
        ("12345678-1234-1234-1234-123456789012", AOA_FRAME_FLAG_TEXT, b"payload")
    ]
```

- [ ] **Step 5: Run tests and confirm they pass**

Run: `python -m pytest dt_image_search/tests/unit/transport/test_aoa_frame_codec.py -v`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add dt_image_search/mobile/transport/aoa_frame_codec.py dt_image_search/tests/unit/transport/test_aoa_frame_codec.py
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: AOA frame codec"
```

---

## Task 2: AOA host driver protocol + simulated implementation

**Files:**
- Create: `dt_image_search/mobile/transport/aoa_host_driver.py`
- Test: `dt_image_search/tests/unit/transport/test_aoa_host_driver.py`

**Interfaces:**
- Consumes: `AoaFrameCodec` for message framing.
- Produces: `AoaHostDriver` Protocol, `SimulatedAoaHostDriver`, `PyUsbAoaHostDriver`.

- [ ] **Step 1: Write the failing test for simulated hooks**

```python
def test_simulated_hooks_exchanges_a_roundtrip_frame():
    from dt_image_search.mobile.transport.aoa_host_driver import SimulatedAoaHostDriver
    from dt_image_search.mobile.transport.aoa_frame_codec import encode_aoa_frame

    hooks = SimulatedAoaHostDriver()
    hooks.start()
    frame = encode_aoa_frame("12345678-1234-1234-1234-123456789012", b"ping")
    hooks.write_frame(frame)
    assert hooks.read_frame(timeout=0.1) == frame
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `python -m pytest dt_image_search/tests/unit/transport/test_aoa_host_driver.py -v`
Expected: `ImportError`.

- [ ] **Step 3: Implement `aoa_host_driver.py`**

```python
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import hashlib
import queue
import threading
import time
from typing import Any, Protocol

import usb.core as _usb_core
import usb.util as _usb_util


class AoaHostState(str, Enum):
    IDLE = "idle"
    DEVICE_DETECTED = "device_detected"
    ACCESSORY_NEGOTIATING = "accessory_negotiating"
    ACCESSORY_READY = "accessory_ready"
    STREAMING = "streaming"
    DISCONNECTED = "disconnected"
    FAILED = "failed"


@dataclass(frozen=True)
class AoaDetectedDevice:
    id_vendor: int
    id_product: int
    bus: int | None
    address: int | None
    serial_hash: str
    supports_aoa: bool
    is_accessory_mode: bool


class AoaStream(Protocol):
    def read(self, size: int = -1) -> bytes:
        ...

    def write(self, data: bytes) -> int:
        ...

    def close(self) -> None:
        ...


class AoaHostDriver(Protocol):
    def detect_devices(self) -> tuple[AoaDetectedDevice, ...]:
        raise NotImplementedError

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        raise NotImplementedError

    def open_stream(self, device: AoaDetectedDevice) -> tuple[AoaStream, AoaStream]:
        """Return (read_stream, write_stream)."""
        raise NotImplementedError

    def close_stream(self) -> None:
        raise NotImplementedError

    def state(self) -> AoaHostState:
        raise NotImplementedError


class SimulatedAoaHostDriver:
    def __init__(self) -> None:
        self._state = AoaHostState.IDLE
        self._read_queue: queue.Queue[bytes] = queue.Queue()
        self._write_queue: queue.Queue[bytes] = queue.Queue()
        self._device = AoaDetectedDevice(
            id_vendor=0x18D1,
            id_product=0x2D01,
            bus=None,
            address=None,
            serial_hash="simulated",
            supports_aoa=True,
            is_accessory_mode=True,
        )

    def start(self) -> None:
        self._state = AoaHostState.ACCESSORY_READY

    def detect_devices(self) -> tuple[AoaDetectedDevice, ...]:
        return (self._device,)

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        self._state = AoaHostState.ACCESSORY_READY
        return True

    def open_stream(self, device: AoaDetectedDevice) -> tuple[AoaStream, AoaStream]:
        self._state = AoaHostState.STREAMING
        return (_SimulatedQueueReader(self._write_queue), _SimulatedQueueWriter(self._read_queue))

    def close_stream(self) -> None:
        self._state = AoaHostState.DISCONNECTED

    def state(self) -> AoaHostState:
        return self._state

    def read_frame(self, timeout: float | None = None) -> bytes | None:
        try:
            return self._read_queue.get(timeout=timeout or 1.0)
        except queue.Empty:
            return None

    def write_frame(self, frame: bytes) -> None:
        self._write_queue.put(frame)


class _SimulatedQueueReader:
    def __init__(self, source: queue.Queue[bytes]) -> None:
        self._source = source
        self._buffer = b""

    def read(self, size: int = -1) -> bytes:
        while (size < 0 or len(self._buffer) < size) and not self._source.empty():
            try:
                self._buffer += self._source.get(timeout=0.1)
            except queue.Empty:
                break
        if size < 0:
            result, self._buffer = self._buffer, b""
        else:
            result, self._buffer = self._buffer[:size], self._buffer[size:]
        return result

    def close(self) -> None:
        pass


class _SimulatedQueueWriter:
    def __init__(self, sink: queue.Queue[bytes]) -> None:
        self._sink = sink

    def write(self, data: bytes) -> int:
        self._sink.put(data)
        return len(data)

    def close(self) -> None:
        pass


class _UsbAoaEndpointStream:
    def __init__(
        self,
        device_handle: Any,
        interface_number: int,
        endpoint_in: Any,
        endpoint_out: Any,
    ) -> None:
        self._device_handle = device_handle
        self._interface_number = interface_number
        self._endpoint_in = endpoint_in
        self._endpoint_out = endpoint_out

    def read(self, size: int = -1) -> bytes:
        chunk_size = size if size > 0 else 16 * 1024
        data = self._endpoint_in.read(chunk_size, timeout=1000)
        return bytes(data)

    def write(self, data: bytes) -> int:
        return int(self._endpoint_out.write(data, timeout=5000))

    def close(self) -> None:
        try:
            _usb_util.release_interface(self._device_handle, self._interface_number)
        except Exception:
            pass


class PyUsbAoaHostDriver:
    AOA_GET_PROTOCOL_REQUEST = 51
    AOA_SEND_STRING_REQUEST = 52
    AOA_START_ACCESSORY_REQUEST = 53
    AOA_VENDOR_REQUEST_IN = 0xC0
    AOA_VENDOR_REQUEST_OUT = 0x40
    GOOGLE_VENDOR_ID = 0x18D1
    AOA_ACCESSORY_PRODUCT_IDS = {
        0x2D00, 0x2D01, 0x2D02, 0x2D03, 0x2D04, 0x2D05,
    }

    def __init__(self) -> None:
        self._usb_core = _usb_core
        self._usb_util = _usb_util
        self._usb_error_type: type[BaseException] = RuntimeError
        if self._usb_core is not None:
            usb_error = getattr(self._usb_core, "USBError", None)
            if isinstance(usb_error, type) and issubclass(usb_error, BaseException):
                self._usb_error_type = usb_error
        self._state = AoaHostState.IDLE
        self._active_stream: _UsbAoaEndpointStream | None = None

    def detect_devices(self) -> tuple[AoaDetectedDevice, ...]:
        self._require_pyusb()
        raw_devices = list(self._usb_core.find(find_all=True) or [])
        detected: list[AoaDetectedDevice] = []
        for raw_device in raw_devices:
            id_vendor = int(getattr(raw_device, "idVendor", 0) or 0)
            id_product = int(getattr(raw_device, "idProduct", 0) or 0)
            is_accessory_mode = (
                id_vendor == self.GOOGLE_VENDOR_ID and id_product in self.AOA_ACCESSORY_PRODUCT_IDS
            )
            supports_aoa = is_accessory_mode or self._supports_aoa_protocol(raw_device)
            if not supports_aoa:
                continue
            serial_hash = self._serial_hash(raw_device)
            detected.append(
                AoaDetectedDevice(
                    id_vendor=id_vendor,
                    id_product=id_product,
                    bus=getattr(raw_device, "bus", None),
                    address=getattr(raw_device, "address", None),
                    serial_hash=serial_hash,
                    supports_aoa=True,
                    is_accessory_mode=is_accessory_mode,
                )
            )
        return tuple(detected)

    def ensure_accessory_mode(self, device: AoaDetectedDevice) -> bool:
        if device.is_accessory_mode:
            return True
        self._require_pyusb()
        device_handle = self._find_device_handle(device)
        if device_handle is None:
            raise RuntimeError("AOA host could not find the selected USB device handle.")
        try:
            protocol_response = device_handle.ctrl_transfer(
                self.AOA_VENDOR_REQUEST_IN,
                self.AOA_GET_PROTOCOL_REQUEST,
                0,
                0,
                2,
                timeout=1500,
            )
            protocol_version = 0
            if len(protocol_response) == 2:
                protocol_version = int(protocol_response[0]) | (int(protocol_response[1]) << 8)
            if protocol_version <= 0:
                raise RuntimeError("AOA protocol version is unavailable on detected device.")
            for string_index, string_value in enumerate(
                (
                    "AuSearch",
                    "AuBackup AOA",
                    "AOA backup transport",
                    "1.0",
                    "https://www.boldman.net",
                    "aubackup",
                )
            ):
                device_handle.ctrl_transfer(
                    self.AOA_VENDOR_REQUEST_OUT,
                    self.AOA_SEND_STRING_REQUEST,
                    0,
                    string_index,
                    string_value.encode("utf-8"),
                    timeout=1500,
                )
            device_handle.ctrl_transfer(
                self.AOA_VENDOR_REQUEST_OUT,
                self.AOA_START_ACCESSORY_REQUEST,
                0,
                0,
                b"",
                timeout=1500,
            )
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA negotiation failed: {exc}") from exc
        finally:
            self._usb_util.dispose_resources(device_handle)

        accessory_deadline = time.monotonic() + 8.0
        while time.monotonic() < accessory_deadline:
            for detected_device in self.detect_devices():
                if detected_device.is_accessory_mode:
                    return True
            time.sleep(0.3)
        return False

    def open_stream(self, device: AoaDetectedDevice) -> tuple[AoaStream, AoaStream]:
        self._require_pyusb()
        device_handle = self._find_device_handle(device)
        if device_handle is None:
            raise RuntimeError("AOA host could not find USB device for stream.")
        try:
            try:
                configuration = device_handle.get_active_configuration()
            except self._usb_error_type:
                device_handle.set_configuration()
                configuration = device_handle.get_active_configuration()
            interface = configuration[(0, 0)]
            endpoint_in = self._usb_util.find_descriptor(
                interface,
                custom_match=lambda endpoint: (
                    self._usb_util.endpoint_direction(endpoint.bEndpointAddress)
                    == self._usb_util.ENDPOINT_IN
                ),
            )
            endpoint_out = self._usb_util.find_descriptor(
                interface,
                custom_match=lambda endpoint: (
                    self._usb_util.endpoint_direction(endpoint.bEndpointAddress)
                    == self._usb_util.ENDPOINT_OUT
                ),
            )
            if endpoint_in is None or endpoint_out is None:
                raise RuntimeError("AOA stream requires both IN and OUT bulk endpoints.")
            self._active_stream = _UsbAoaEndpointStream(
                device_handle,
                interface.bInterfaceNumber,
                endpoint_in,
                endpoint_out,
            )
            self._state = AoaHostState.STREAMING
            return (self._active_stream, self._active_stream)
        except self._usb_error_type as exc:
            raise RuntimeError(f"AOA stream open failed: {exc}") from exc

    def close_stream(self) -> None:
        if self._active_stream is not None:
            self._active_stream.close()
            self._active_stream = None
        self._state = AoaHostState.DISCONNECTED

    def state(self) -> AoaHostState:
        return self._state

    def _require_pyusb(self) -> None:
        if self._usb_core is None or self._usb_util is None:
            raise RuntimeError(
                "AOA host requires pyusb (install with `python -m pip install pyusb`)."
            )

    def _find_device_handle(self, device: AoaDetectedDevice) -> Any | None:
        self._require_pyusb()
        found = self._usb_core.find(
            idVendor=device.id_vendor,
            idProduct=device.id_product,
            bus=device.bus,
            address=device.address,
        )
        if found is not None:
            return found
        return self._usb_core.find(idVendor=device.id_vendor, idProduct=device.id_product)

    def _supports_aoa_protocol(self, device_handle: Any) -> bool:
        try:
            protocol_response = device_handle.ctrl_transfer(
                self.AOA_VENDOR_REQUEST_IN,
                self.AOA_GET_PROTOCOL_REQUEST,
                0,
                0,
                2,
                timeout=600,
            )
            return len(protocol_response) == 2
        except self._usb_error_type:
            return False

    def _serial_hash(self, device_handle: Any) -> str:
        serial_value = ""
        try:
            serial_value = str(getattr(device_handle, "serial_number", "") or "")
        except self._usb_error_type:
            serial_value = ""
        if not serial_value:
            serial_value = (
                f"{getattr(device_handle, 'bus', 'unknown')}-"
                f"{getattr(device_handle, 'address', 'unknown')}"
            )
        return hashlib.sha256(serial_value.encode("utf-8")).hexdigest()

- [ ] **Step 5: Run tests**

Run: `python -m pytest dt_image_search/tests/unit/transport/test_aoa_host_driver.py -v`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add dt_image_search/mobile/transport/aoa_host_driver.py dt_image_search/tests/unit/transport/test_aoa_host_driver.py
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: AOA host driver protocol and simulated hooks"
```

---

## Task 3: `UsbAoaTransportAdapter` implementation

**Files:**
- Create: `dt_image_search/mobile/transport/usb_aoa_adapter.py`
- Test: `dt_image_search/tests/unit/transport/test_usb_aoa_adapter.py`

**Interfaces:**
- Consumes: `MobileTransportRouter`, `AoaHostDriver`, `AoaFrameCodec`, `TransferAssetUploadStream`, `MobilePayloadEncryption`.
- Produces: `UsbAoaTransportAdapter` with `configure_bootstrap`, `start`, `stop`, `state`, `bootstrap_config`, `last_probe_error`.

- [ ] **Step 1: Write a failing test for adapter bootstrap and auth**

```python
def test_aoa_adapter_authenticates_and_routes_pairing_claim():
    from dt_image_search.mobile.transport.contracts import MobileTransportRouter
    from dt_image_search.mobile.transport.aoa_host_driver import SimulatedAoaHostDriver
    from dt_image_search.mobile.transport.usb_aoa_adapter import UsbAoaTransportAdapter
    from dt_image_search.mobile.transport.contracts import MobileTransportRequest, MobileTransportResponse

    router = MobileTransportRouter()
    def handle_claim(request: MobileTransportRequest) -> MobileTransportResponse:
        return MobileTransportResponse(status_code=200, payload={"status": "accepted"})
    router.register("pairing.claim", handle_claim)

    hooks = SimulatedAoaHostDriver()
    hooks.start()
    adapter = UsbAoaTransportAdapter(router=router, tunnel_provider=hooks)
    adapter.configure_bootstrap(
        session_id="sid-001",
        one_time_passcode="123456",
        suggested_port=45000,
    )
    adapter.start()

    # Simulate mobile auth response
    from dt_image_search.mobile.transport.aoa_frame_codec import encode_aoa_frame
    import json
    auth_response = {
        "schema": "dtis.mobile-transport.v1",
        "request_id": "auth-challenge",
        "status_code": 200,
        "body": {
            "schema": "dtis.mobile-pairing.v1",
            "status": "accepted",
            "proof": "unused-in-simulated",
        },
    }
    read_stream, write_stream = hooks.open_stream(hooks.detect_devices()[0])
    write_stream.write(encode_aoa_frame("auth-challenge", json.dumps(auth_response, separators=(",", ":"), sort_keys=True).encode("utf-8")))

    # Wait for the adapter to become authenticated
    for _ in range(50):
        if adapter.state == "connected":
            break
        time.sleep(0.01)
    assert adapter.state == "connected"

    # Send a pairing claim and wait for response
    claim_request = {
        "schema": "dtis.mobile-transport.v1",
        "operation": "pairing.claim",
        "request_id": "claim-001",
        "body_schema": "dtis.mobile-pairing.v1",
        "body": {"schema": "dtis.mobile-pairing.v1", "sid": "sid-001", "opt": "123456"},
    }
    write_stream.write(encode_aoa_frame("claim-001", json.dumps(claim_request, separators=(",", ":"), sort_keys=True).encode("utf-8")))

    response = None
    for _ in range(100):
        frame = hooks.read_frame(timeout=0.1)
        if frame:
            from dt_image_search.mobile.transport.aoa_frame_codec import decode_aoa_frame
            _, _, payload = decode_aoa_frame(frame)
            response = json.loads(payload)
            if response.get("request_id") == "claim-001":
                break
        time.sleep(0.01)
    assert response is not None
    assert response["status_code"] == 200
    assert response["body"]["status"] == "accepted"
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `python -m pytest dt_image_search/tests/unit/transport/test_usb_aoa_adapter.py -v`
Expected: `ImportError` or failure because `UsbAoaTransportAdapter` does not exist.

- [ ] **Step 3: Implement `usb_aoa_adapter.py`**

The adapter should mirror the structure of `usb_ws_adapter.py`:

- `UsbAoaTransportAdapter` with a `threading.Thread` probe loop.
- `configure_bootstrap(config)` stores the bootstrap config.
- `start()` starts the probe loop.
- `stop()` stops the loop and closes streams.
- `_probe()` calls `detect_devices`, `ensure_accessory_mode`, `open_stream`, then runs `_auth_challenge()` and `_session_loop()`.
- `_auth_challenge()` sends the `transport.auth.challenge` envelope and waits for the proof; validate it with `SHA256(opt + rand)`.
- `_session_loop()` reads frames using `AoaFrameDecoder`, dispatches text envelopes to `router`, handles binary chunks via `TransferAssetUploadStream`, and writes response frames.
- `_send_frame()` writes an encoded frame to the output stream.
- `_dispatch_envelope_request()` is copied from `usb_ws_adapter.py` because the envelope and asset-stream logic are identical.

Key code skeleton:

```python
from __future__ import annotations

import hashlib
import json
import secrets
import threading
import time
from typing import Any, BinaryIO, Callable

from dt_image_search.mobile.transport.aoa_frame_codec import (
    AOA_FRAME_FLAG_BINARY,
    AOA_FRAME_FLAG_TEXT,
    AoaFrameDecoder,
    encode_aoa_frame,
)
from dt_image_search.mobile.transport.aoa_host_driver import AoaHostDriver, AoaHostState
from dt_image_search.mobile.transport.asset_upload_stream import (
    TRANSFER_ASSET_STREAM_CHUNK_SIZE_BYTES,
    TRANSFER_ASSET_STREAM_STATE_COMPLETE,
    TRANSFER_ASSET_STREAM_STATE_FIELD,
    TRANSFER_ASSET_STREAM_STATE_START,
    TransferAssetUploadStream,
)
from dt_image_search.mobile.transport.contracts import (
    MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
    TRANSFER_ASSET_OPERATION,
    MobileTransportContext,
    MobileTransportKind,
    MobileTransportRequest,
    MobileTransportResponse,
    TransferAssetUploadPayload,
    UsbBootstrapConfig,
)
from dt_image_search.mobile.transport.router import MobileTransportRouteNotFoundError, MobileTransportRouter
from dt_image_search.mobile.mobile_payload_encryption import (
    MobilePayloadEncryptionError,
    decrypt_mobile_binary_chunk,
    decrypt_mobile_json_payload,
    is_mobile_encrypted_payload,
)
from dt_image_search.telemetry.telemetry_client import log

USB_AUTH_CHALLENGE_OPERATION = "transport.auth.challenge"
USB_AUTH_CHALLENGE_BODY_SCHEMA = "dtis.mobile-pairing.v1"
USB_AUTH_CHALLENGE_REQUEST_ID = "auth-challenge"
USB_AUTH_CHALLENGE_TIMEOUT_SECONDS = 2.0


class UsbAoaTransportAdapter:
    def __init__(
        self,
        *,
        router: MobileTransportRouter,
        tunnel_provider: AoaHostDriver,
        probe_interval_seconds: float = 0.6,
        response_poll_timeout_seconds: float = 0.6,
        log_handler: Callable[..., None] | None = None,
        resolve_transfer_trust_key: Callable[..., str | None] | None = None,
    ) -> None:
        self._router = router
        self._tunnel_provider = tunnel_provider
        self._probe_interval_seconds = probe_interval_seconds
        self._response_poll_timeout_seconds = response_poll_timeout_seconds
        self._log_handler = log_handler
        self._resolve_transfer_trust_key = resolve_transfer_trust_key
        self._lock = threading.RLock()
        self._stop_event = threading.Event()
        self._worker_thread: threading.Thread | None = None
        self._bootstrap_config: UsbBootstrapConfig | None = None
        self._state = "stopped"
        self._read_stream: BinaryIO | None = None
        self._write_stream: BinaryIO | None = None
        self._asset_upload_stream = TransferAssetUploadStream()
        self._last_probe_error: str | None = None

    @property
    def state(self) -> str:
        with self._lock:
            return self._state

    @property
    def bootstrap_config(self) -> UsbBootstrapConfig | None:
        with self._lock:
            return self._bootstrap_config

    @property
    def last_probe_error(self) -> str | None:
        with self._lock:
            return self._last_probe_error

    def configure_bootstrap(self, config: UsbBootstrapConfig) -> None:
        with self._lock:
            self._bootstrap_config = config
            self._state = "configured"
            self._close_streams_locked()
        self._safe_log("info", message=f"UsbAoaTransportAdapter/configure_bootstrap sid={config.session_id}")

    def start(self) -> None:
        with self._lock:
            self._stop_event.clear()
            if self._worker_thread is None or not self._worker_thread.is_alive():
                self._worker_thread = threading.Thread(
                    target=self._run_transport_loop,
                    name="mobile-usb-aoa-transport",
                    daemon=True,
                )
                self._worker_thread.start()

    def stop(self) -> None:
        with self._lock:
            self._stop_event.set()
            self._state = "stopped"
            self._close_streams_locked()
            thread = self._worker_thread
            self._worker_thread = None
        if thread is not None and thread.is_alive():
            thread.join(timeout=2.0)

    def _run_transport_loop(self) -> None:
        while not self._stop_event.is_set():
            config = self._bootstrap_config
            if config is None:
                self._stop_event.wait(timeout=self._probe_interval_seconds)
                continue
            try:
                devices = self._tunnel_provider.detect_devices()
            except Exception as exc:
                self._set_probe_error(str(exc))
                self._stop_event.wait(timeout=self._probe_interval_seconds)
                continue
            if not devices:
                self._set_probe_error("No AOA-capable Android device detected.")
                self._stop_event.wait(timeout=self._probe_interval_seconds)
                continue
            device = devices[0]
            try:
                if not self._tunnel_provider.ensure_accessory_mode(device):
                    self._set_probe_error("Device did not enter AOA accessory mode.")
                    self._stop_event.wait(timeout=self._probe_interval_seconds)
                    continue
                read_stream, write_stream = self._tunnel_provider.open_stream(device)
                self._read_stream = read_stream
                self._write_stream = write_stream
                self._set_state("ready")
                self._perform_auth_challenge(read_stream, write_stream)
                self._set_state("connected")
                self._session_loop(read_stream, write_stream)
            except Exception as exc:
                self._set_probe_error(str(exc))
            finally:
                self._tunnel_provider.close_stream()
                with self._lock:
                    self._read_stream = None
                    self._write_stream = None
                self._set_state("ready")
            self._stop_event.wait(timeout=self._probe_interval_seconds)

    def _perform_auth_challenge(self, read_stream: BinaryIO, write_stream: BinaryIO) -> None:
        config = self._require_bootstrap_config()
        rand = secrets.token_hex(16)
        challenge = {
            "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
            "operation": USB_AUTH_CHALLENGE_OPERATION,
            "request_id": USB_AUTH_CHALLENGE_REQUEST_ID,
            "body_schema": USB_AUTH_CHALLENGE_BODY_SCHEMA,
            "body": {
                "schema": USB_AUTH_CHALLENGE_BODY_SCHEMA,
                "sid": config.session_id,
                "rand": rand,
            },
        }
        self._send_frame(write_stream, USB_AUTH_CHALLENGE_REQUEST_ID, json.dumps(challenge, separators=(",", ":"), sort_keys=True).encode("utf-8"))
        deadline = time.monotonic() + USB_AUTH_CHALLENGE_TIMEOUT_SECONDS
        decoder = AoaFrameDecoder()
        while time.monotonic() < deadline:
            data = read_stream.read(8192)
            if data:
            for request_id, flags, payload in decoder.feed(data):
                if request_id != USB_AUTH_CHALLENGE_REQUEST_ID:
                    continue
                if flags != AOA_FRAME_FLAG_TEXT:
                    continue
                response = json.loads(payload)
                if response.get("status_code") not in range(200, 300):
                    raise RuntimeError("AOA auth challenge rejected")
                body = response.get("body", {})
                provided = body.get("proof", "")
                expected = hashlib.sha256(f"{config.one_time_passcode}{rand}".encode("utf-8")).hexdigest()
                if provided != expected:
                    raise RuntimeError("AOA auth challenge proof mismatch")
                return
            else:
                time.sleep(0.01)
        raise RuntimeError("AOA auth challenge timed out")

    def _session_loop(self, read_stream: BinaryIO, write_stream: BinaryIO) -> None:
        decoder = AoaFrameDecoder()
        while not self._stop_event.is_set():
            try:
                data = read_stream.read(8192)
            except Exception as exc:
                self._safe_log("warning", message=f"AOA read failed: {exc}")
                break
            if not data:
                time.sleep(0.01)
                continue
            for request_id, flags, payload in decoder.feed(data):
                if flags == AOA_FRAME_FLAG_BINARY:
                    self._append_aoa_binary_chunk(
                        request_id=request_id,
                        payload=payload,
                    )
                    continue
                request_id_out, response = self._dispatch_envelope_request(payload)
                if response is not None and request_id_out is not None:
                    self._send_frame(
                        write_stream,
                        request_id_out,
                        json.dumps({
                            "schema": MOBILE_TRANSPORT_ENVELOPE_SCHEMA,
                            "request_id": request_id_out,
                            "status_code": response.status_code,
                            "body": response.payload,
                        }, separators=(",", ":"), sort_keys=True).encode("utf-8"),
                    )

    def _send_frame(
        self,
        write_stream: BinaryIO,
        request_id: str,
        payload: bytes,
        flags: int = AOA_FRAME_FLAG_TEXT,
    ) -> None:
        frame = encode_aoa_frame(request_id, payload, flags=flags)
        write_stream.write(frame)

    def _dispatch_envelope_request(self, raw_payload: bytes) -> tuple[str | None, MobileTransportResponse | None]:
        # Copy the dispatch and transfer-asset logic from usb_ws_adapter.py,
        # substituting the websocket send path with in-memory response returns.
        # For binary asset responses, call _send_frame with flags=AOA_FRAME_FLAG_BINARY.
        ...

    def _append_aoa_binary_chunk(
        self,
        *,
        request_id: str,
        payload: bytes,
    ) -> None:
        # Append raw chunk bytes for the active streaming request_id.
        # Decrypt with the trust key returned by _asset_upload_stream.encryption_trust_key.
        # Reuse the AssetUploadStream logic from usb_ws_adapter.py.
        ...

    def _require_bootstrap_config(self) -> UsbBootstrapConfig:
        with self._lock:
            if self._bootstrap_config is None:
                raise RuntimeError("USB bootstrap config is not available")
            return self._bootstrap_config

    def _set_state(self, state: str) -> None:
        with self._lock:
            self._state = state

    def _set_probe_error(self, message: str | None) -> None:
        with self._lock:
            self._last_probe_error = message

    def _close_streams_locked(self) -> None:
        if self._read_stream:
            try:
                self._read_stream.close()
            except Exception:
                pass
            self._read_stream = None
        if self._write_stream:
            try:
                self._write_stream.close()
            except Exception:
                pass
            self._write_stream = None

    def _safe_log(self, severity: str, *, message: str, **kwargs: Any) -> None:
        try:
            if self._log_handler:
                self._log_handler(severity, message=message, **kwargs)
            else:
                log(severity, message=message, **kwargs)
        except Exception:
            pass
```

Complete the `_dispatch_envelope_request` and `_append_aoa_binary_chunk` methods by copying the equivalent sections from `usb_ws_adapter.py` and adapting the `websocket_connection.send` calls to return the response instead of sending. Note that AOA binary chunks carry no inner frame header; use the request_id/flags from the outer AOA frame and pass the raw payload bytes directly.

- [ ] **Step 4: Run tests and confirm they pass**

Run: `python -m pytest dt_image_search/tests/unit/transport/test_usb_aoa_adapter.py -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add dt_image_search/mobile/transport/usb_aoa_adapter.py dt_image_search/tests/unit/transport/test_usb_aoa_adapter.py
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: desktop AOA USB transport adapter"
```

---

## Task 4: Integrate with `MobileTransportManager`

**Files:**
- Modify: `dt_image_search/mobile/transport/transport_manager.py`
- Modify: `dt_image_search/mobile/transport/__init__.py`

**Interfaces:**
- Consumes: `UsbAoaTransportAdapter`.
- Produces: `MobileTransportManager` exposes `start_aoa`, `stop_aoa`, `configure_aoa_bootstrap`, `aoa_state`, `aoa_bootstrap_config`, `aoa_last_probe_error`.

- [ ] **Step 1: Modify `transport_manager.py`**

```python
from __future__ import annotations

from dt_image_search.mobile.transport.lan_http_adapter import LanHttpEndpointInfo, LanHttpTransportAdapter
from dt_image_search.mobile.transport.usb_aoa_adapter import UsbAoaTransportAdapter
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
        aoa_transport: UsbAoaTransportAdapter,
    ):
        self._lan_transport = lan_transport
        self._usb_transport = usb_transport
        self._aoa_transport = aoa_transport

    def start_lan(self) -> LanHttpEndpointInfo:
        return self._lan_transport.start()

    def stop_all(self) -> None:
        self._aoa_transport.stop()
        self._usb_transport.stop()
        self._lan_transport.stop()

    def configure_aoa_bootstrap(self, config: UsbBootstrapConfig) -> None:
        self._aoa_transport.configure_bootstrap(config)

    def start_aoa(self) -> str:
        self._aoa_transport.start()
        return self._aoa_transport.state

    def stop_aoa(self) -> None:
        self._aoa_transport.stop()

    @property
    def aoa_state(self) -> str:
        return self._aoa_transport.state

    @property
    def aoa_bootstrap_config(self) -> UsbBootstrapConfig | None:
        return self._aoa_transport.bootstrap_config

    @property
    def aoa_last_probe_error(self) -> str | None:
        return self._aoa_transport.last_probe_error
```

- [ ] **Step 2: Update `__init__.py` exports**

```python
from dt_image_search.mobile.transport.aoa_frame_codec import (
    AoaFrameDecoder,
    decode_aoa_frame,
    encode_aoa_frame,
)
from dt_image_search.mobile.transport.aoa_host_driver import (
    AoaDetectedDevice,
    AoaHostDriver,
    AoaHostState,
    PyUsbAoaHostDriver,
    SimulatedAoaHostDriver,
)
from dt_image_search.mobile.transport.usb_aoa_adapter import UsbAoaTransportAdapter

__all__ = [
    "CAPABILITY_EXCHANGE_OPERATION",
    "PAIRING_CLAIM_OPERATION",
    "UPDATE_PROMPT_OPERATION",
    "TRANSFER_START_OPERATION",
    "TRANSFER_EXISTENCE_OPERATION",
    "TRANSFER_ASSET_OPERATION",
    "TRANSFER_COMPLETE_OPERATION",
    "MobileTransportKind",
    "MobileTransportContext",
    "MobileTransportRequest",
    "MobileTransportResponse",
    "TransferAssetUploadPayload",
    "MobileTransportRouteNotFoundError",
    "MobileTransportRouter",
    "MOBILE_TRANSPORT_ENVELOPE_SCHEMA",
    "UsbBootstrapConfig",
    "UsbTunnelTarget",
    "UsbTransportState",
    "UsbWebSocketTransportAdapter",
    "iter_usb_probe_ports",
    "UsbConnectedDevice",
    "UsbTunnelProvider",
    "UsbTunnelUnavailableError",
    "UsbTunnelDeviceNotFoundError",
    "UsbTunnelConnectError",
    "Pymobiledevice3UsbTunnelProvider",
    "MobileTransportManager",
    "AoaFrameDecoder",
    "decode_aoa_frame",
    "encode_aoa_frame",
    "AoaDetectedDevice",
    "AoaHostDriver",
    "AoaHostState",
    "PyUsbAoaHostDriver",
    "SimulatedAoaHostDriver",
    "UsbAoaTransportAdapter",
]
```

- [ ] **Step 3: Add/update tests for `MobileTransportManager`**

```python
def test_transport_manager_starts_and_stops_aoa():
    from dt_image_search.mobile.transport.transport_manager import MobileTransportManager
    from dt_image_search.mobile.transport.aoa_host_driver import SimulatedAoaHostDriver
    from dt_image_search.mobile.transport.usb_aoa_adapter import UsbAoaTransportAdapter
    from dt_image_search.mobile.transport.router import MobileTransportRouter

    hooks = SimulatedAoaHostDriver()
    hooks.start()
    aoa = UsbAoaTransportAdapter(router=MobileTransportRouter(), tunnel_provider=hooks)
    manager = MobileTransportManager(
        lan_transport=MockLanTransport(),
        usb_transport=MockUsbTransport(),
        aoa_transport=aoa,
    )
    manager.configure_aoa_bootstrap(
        session_id="sid",
        one_time_passcode="opt",
        suggested_port=45000,
    )
    assert manager.aoa_state == "configured"
    manager.start_aoa()
    assert manager.aoa_state in {"ready", "connected", "stopped"}
    manager.stop_aoa()
    assert manager.aoa_state == "stopped"
```

- [ ] **Step 4: Run tests**

Run: `python -m pytest dt_image_search/tests/unit/transport/ -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add dt_image_search/mobile/transport/transport_manager.py dt_image_search/mobile/transport/__init__.py dt_image_search/tests/unit/transport/test_transport_manager.py
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: integrate AOA adapter into transport manager"
```

---

## Task 5: Self-review

- [ ] Verify that every requirement in `docs/superpowers/specs/2026-07-28-android-aoa-usb-backup-transport-design.md` has a corresponding task.
- [ ] Search the plan for "TODO", "TBD", "implement later" — none should appear.
- [ ] Confirm that method names (`configure_bootstrap`, `start`, `stop`, `state`, `last_probe_error`) match the existing `UsbWebSocketTransportAdapter` contract.
- [ ] Confirm that the AOA frame header constants match the spec: version 1, request_id 36 bytes, header 42 bytes.
- [ ] Confirm that the auth proof uses `SHA256(opt + rand)` exactly as the spec and iOS implementation do.

If gaps are found, fix them before marking the plan complete.
