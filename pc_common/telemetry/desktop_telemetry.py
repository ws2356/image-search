# Desktop telemetry bootstrap: the single place where every desktop process
# entry point (Qt app, shell, index server, instant-share agent) wires
# telemetry with its own identity and the shared rotating local log file.
# Author: ws2356, 2026-10-09
import uuid

from pc_common.dts_logging import get_other_handlers
from pc_common.model.dt_device_id import get_device_id
from pc_common.model.dts_config import get_log_level, get_revision
from pc_common.model.feature_flags import get_desktop_root_trace_sample_rate
from pc_common.telemetry.runtime_metadata import RESOURCE_ATTRIBUTES
from pc_common.telemetry.telemetry_client import init_telemetry
from pc_common.tools.dt_is_debug import is_debug


def init_desktop_telemetry(service_name: str, debug_mode: bool | None = None) -> None:
    """Initialize telemetry for one desktop process entry point.

    Args:
        service_name: OTel identity of the calling process; each entry point
            owns an explicit name (client, shell, server, agent).
        debug_mode: Overrides source-vs-frozen detection when a process
            intentionally must keep stdout/stderr intact (e.g. the index
            server's DTS_READY stdout handshake).
    """
    init_telemetry(
        device_id=get_device_id(),
        session_id=str(uuid.uuid4()),
        revision=get_revision(),
        log_level=get_log_level(),
        root_trace_sample_rate=get_desktop_root_trace_sample_rate(),
        service_name=service_name,
        resource_attributes=RESOURCE_ATTRIBUTES,
        log_handlers=get_other_handlers(),
        debug_mode=is_debug() if debug_mode is None else debug_mode,
    )
