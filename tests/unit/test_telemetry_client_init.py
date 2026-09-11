from pc_common.telemetry.telemetry_client import init_telemetry
from pc_common.telemetry.telemetry_client import log


def test_init_telemetry_requires_service_name() -> None:
    try:
        init_telemetry(
            device_id="device",
            session_id="session",
            revision="revision",
            log_level=0,
            root_trace_sample_rate=1.0,
            resource_attributes={},
            log_handlers=[],
            debug_mode=True,
        )
    except TypeError as exc:
        assert "service_name" in str(exc)
    else:
        raise AssertionError("service_name must be required by init_telemetry()")


def test_logging_uses_injected_service_name() -> None:
    init_telemetry(
        device_id="device",
        session_id="session",
        revision="revision",
        log_level=0,
        root_trace_sample_rate=1.0,
        service_name="test_telemetry_client",
        resource_attributes={},
        log_handlers=[],
        debug_mode=True,
    )
    log("info", "test", "message")

    import logging

    assert logging.getLogger("test_telemetry_client").name == "test_telemetry_client"
