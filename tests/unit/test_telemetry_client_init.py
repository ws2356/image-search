from pc_common.telemetry.telemetry_client import init_telemetry


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
