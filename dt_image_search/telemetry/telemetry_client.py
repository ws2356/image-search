from contextlib import contextmanager
from functools import wraps
import logging
import os
import sys
import threading
from collections.abc import Sequence
from urllib.parse import urlparse

# Ensure nuitka include this module which would otherwise be loaded dynamically
import opentelemetry.context.contextvars_context

from opentelemetry import trace, metrics
from opentelemetry.propagate import extract
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.sampling import ParentBased, TraceIdRatioBased
from opentelemetry.sdk.metrics import MeterProvider, Counter, UpDownCounter, Histogram, ObservableCounter, ObservableUpDownCounter, ObservableGauge
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader, ConsoleMetricExporter, AggregationTemporality

from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from dt_image_search.dts_logging import get_other_handlers
from dt_image_search.model.dt_device_id import get_device_id
from dt_image_search.model.dt_session_id import session_id
from dt_image_search.telemetry.otlp_settings import EXPORT_BATCH_SIZE, EXPORT_QUEUE_SIZE, EXPORT_TIMEOUT_SECONDS, LOGS_UPLOAD_ENDPOINT, METRICS_UPLOAD_ENDPOINT, TELEMETRY_UPLOAD_HOST, TRACES_UPLOAD_ENDPOINT
from dt_image_search.telemetry.runtime_metadata import RESOURCE_ATTRIBUTES
from dt_image_search.model.dts_config import get_log_level, get_revision
from dt_image_search.model.feature_flags import get_desktop_root_trace_sample_rate


_telemetry_upload_host = TELEMETRY_UPLOAD_HOST
_metrics_upload_endpoint = METRICS_UPLOAD_ENDPOINT
_traces_upload_endpoint = TRACES_UPLOAD_ENDPOINT
_logs_upload_endpoint = LOGS_UPLOAD_ENDPOINT
_session_id_attribute = "app.session.id"
_device_id_attribute = "app.device.id"
_revision_attribute = "app.revision"

_image_search_client = "imagesearch_client"

_resource = Resource.create(attributes={
    "service.name": _image_search_client,
    _device_id_attribute: get_device_id(),
    _revision_attribute: get_revision(),
    **RESOURCE_ATTRIBUTES,
})
_BATCH_SIZE = EXPORT_BATCH_SIZE
_QUEUE_SIZE = EXPORT_QUEUE_SIZE
_ROOT_SPAN_SAMPLE_RATE = get_desktop_root_trace_sample_rate()

# === METRICS SETUP ===
temporality = {
                Counter: AggregationTemporality.CUMULATIVE,
                UpDownCounter: AggregationTemporality.CUMULATIVE,
                Histogram: AggregationTemporality.CUMULATIVE,
                ObservableCounter: AggregationTemporality.CUMULATIVE,
                ObservableUpDownCounter: AggregationTemporality.CUMULATIVE,
                ObservableGauge: AggregationTemporality.CUMULATIVE,
            }
_metric_exporter = OTLPMetricExporter(endpoint=_metrics_upload_endpoint, preferred_temporality=temporality, timeout=EXPORT_TIMEOUT_SECONDS)
metric_readers = [PeriodicExportingMetricReader(_metric_exporter, export_interval_millis=60_000)]
if sys.stdout is not None and sys.stderr is not None:
    _metric_exporter2 = ConsoleMetricExporter(preferred_temporality=temporality)
    metric_reader2 = PeriodicExportingMetricReader(_metric_exporter2, export_interval_millis=60_000)
    metric_readers.append(metric_reader2)
metrics.set_meter_provider(MeterProvider(metric_readers=metric_readers, resource=_resource))
_meter = metrics.get_meter(_image_search_client)

# Counters
startup_counter = _meter.create_counter("app_startups")
search_counter = _meter.create_counter("search")
error_counter = _meter.create_counter("errors")

# === TRACING SETUP ===
trace.set_tracer_provider(
    TracerProvider(
        resource=_resource,
        sampler=ParentBased(root=TraceIdRatioBased(_ROOT_SPAN_SAMPLE_RATE)),
    )
)
_trace_exporter = OTLPSpanExporter(endpoint=_traces_upload_endpoint, timeout=EXPORT_TIMEOUT_SECONDS)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(_trace_exporter, schedule_delay_millis=60_000, max_export_batch_size=_BATCH_SIZE, max_queue_size=_QUEUE_SIZE))
if sys.stdout is not None and sys.stderr is not None:
    trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(ConsoleSpanExporter(), schedule_delay_millis=60_000, max_export_batch_size=_BATCH_SIZE, max_queue_size=_QUEUE_SIZE))
tracer = trace.get_tracer(_image_search_client)

# === LOGGING SETUP ===
_logger_provider = LoggerProvider(resource=_resource)
_log_exporter = OTLPLogExporter(endpoint=_logs_upload_endpoint, timeout=EXPORT_TIMEOUT_SECONDS)
_logger_provider.add_log_record_processor(BatchLogRecordProcessor(_log_exporter, schedule_delay_millis=60_000, max_export_batch_size=_BATCH_SIZE, max_queue_size=_QUEUE_SIZE))
# otel_logger = _logger_provider.get_logger(_image_search_client)

# Temporary workaround to fix log loop: otel log handler -> upload via urllib3 -> urllib3 internal log -> otel log handler
class OtelLogFilter(logging.Filter):
    def __init__(self):
        super().__init__()
        # parse _telemetry_upload_host extracting host
        self.telemetry_host = urlparse(_telemetry_upload_host).hostname

    def filter(self, record):
        if record.module != 'connectionpool':
            return True
        # Iterate values of record.args tuple
        if not isinstance(record.args, tuple):
            return True
        for arg in record.args:
            if arg == self.telemetry_host:
                return False
        return True


class OtelContextFilter(logging.Filter):
    def filter(self, record):
        setattr(record, _session_id_attribute, session_id)
        return True


_reserved_log_record_keys = frozenset(logging.makeLogRecord({}).__dict__.keys())


_otel_attribute_primitive_types = (bool, bytes, int, float, str)


def _is_valid_otel_attribute_sequence(value: object) -> bool:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        return False
    sequence_item_types: set[type] = set()
    for item in value:
        if not isinstance(item, _otel_attribute_primitive_types):
            return False
        sequence_item_types.add(type(item))
    return len(sequence_item_types) <= 1


def _is_valid_otel_attribute_value(value: object) -> bool:
    if value is None or isinstance(value, _otel_attribute_primitive_types):
        return True
    return _is_valid_otel_attribute_sequence(value)


def _normalize_otel_attributes(
    attributes: dict[str, object] | None,
    *,
    allow_none: bool = False,
) -> dict[str, object]:
    if not attributes:
        return {}

    normalized: dict[str, object] = {}
    for key, value in attributes.items():
        if not isinstance(key, str) or not key:
            continue
        if value is None and not allow_none:
            continue
        if _is_valid_otel_attribute_value(value):
            normalized[key] = value
        else:
            normalized[key] = repr(value)
    return normalized


def _extract_remote_context(carrier: dict[str, object] | None):
    if not carrier:
        return None

    propagation_carrier: dict[str, str] = {}
    for header_name in ("traceparent", "tracestate"):
        header_value = carrier.get(header_name)
        if isinstance(header_value, str) and header_value.strip():
            propagation_carrier[header_name] = header_value.strip()

    if not propagation_carrier:
        return None
    return extract(propagation_carrier)


class OtelAttributeSanitizerFilter(logging.Filter):
    """Normalize custom LogRecord extras to OTEL-supported attribute types."""

    def filter(self, record):
        record_dict = record.__dict__
        for key, value in list(record_dict.items()):
            if key in _reserved_log_record_keys:
                continue
            if _is_valid_otel_attribute_value(value):
                continue
            record_dict[key] = repr(value)
        return True


# Open the system’s null device for writing:
# ── '/dev/null' on Unix, 'nul' on Windows
# Redirect both Python stdout and stderr so that naive dependencies that write to stdout/stderr won't break the app
from dt_image_search.tools.dt_is_debug import is_debug
if not is_debug() and "PYTEST_CURRENT_TEST" not in os.environ:
    devnull = open(os.devnull, 'w', encoding='utf-8')
    sys.stdout = devnull
    sys.stderr = devnull

_logger = None
_lock = threading.Lock()
def log(
    severity: str,
    error_type: str = "",
    message: str = "",
    where: str = "",
    attributes: dict[str, object] | None = None,
):
    # Lazy init logger to prevent circular import issues
    global _logger
    with _lock:
        if _logger is None:
            # Setup logger only once
            level = get_log_level()
            if "PYTEST_CURRENT_TEST" in os.environ:
                level = logging.DEBUG
            handlers = get_other_handlers()
            if os.getenv('IS_TESTING', 'false') != 'true':
                logging_handler = LoggingHandler(level=level, logger_provider=_logger_provider)
                logging_handler.addFilter(OtelAttributeSanitizerFilter())
                logging_handler.addFilter(OtelLogFilter())
                logging_handler.addFilter(OtelContextFilter())
                handlers.insert(0, logging_handler)
            logging.basicConfig(level=level, handlers=handlers)
            _logger = logging.getLogger(_image_search_client)
    if severity not in ["debug", "info", "warning", "error"]:
        raise ValueError(f"Invalid log severity: {severity}")
    log_function = getattr(_logger, severity, _logger.info)
    if severity in ["error"] and error_type:
        # Get current trace_id
        error_counter.add(1, {"type": error_type, "location": where})
    extra = {
        key: value
        for key, value in _normalize_otel_attributes(attributes, allow_none=False).items()
        if key not in _reserved_log_record_keys
    }
    log_function(
        f"{error_type} at {where}: {message}",
        extra=extra or None,
    )


@contextmanager
def add_span(
    name: str,
    attributes: dict[str, object] | None = None,
    carrier: dict[str, object] | None = None,
):
    """Context manager for tracing blocks of code."""
    with tracer.start_as_current_span(
        name,
        context=_extract_remote_context(carrier),
    ) as span:
        span.set_attribute(_session_id_attribute, session_id)
        for key, value in _normalize_otel_attributes(attributes, allow_none=False).items():
            span.set_attribute(key, value)
        yield span

def with_trace(name=None):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            span_name = name or func.__name__
            with tracer.start_as_current_span(span_name) as span:
                span.set_attribute(_session_id_attribute, session_id)
                return func(*args, **kwargs)
        return wrapper
    return decorator

def flush_telemetry():
    """Flush telemetry data before the application exits."""
    # Flush logs
    _logger_provider.force_flush()
    # Flush traces
    trace.get_tracer_provider().force_flush()
    # Flush metrics
    for reader in metric_readers:
        reader.force_flush()


def _force_flush_with_timeout(flush_callable, timeout_millis: int) -> bool:
    """Best-effort force flush wrapper that prefers timeout-aware APIs."""
    try:
        try:
            result = flush_callable(timeout_millis=timeout_millis)
        except TypeError:
            result = flush_callable()

        if isinstance(result, bool):
            return result
        return True
    except Exception:
        return False


def flush_telemetry_for_fatal(timeout_millis: int = 5000) -> bool:
    """Best-effort bounded flush for crash/fatal paths.

    This method is intentionally tolerant: it never raises and returns whether
    all flush operations reported success.
    """
    all_ok = True

    all_ok = _force_flush_with_timeout(_logger_provider.force_flush, timeout_millis) and all_ok
    all_ok = _force_flush_with_timeout(trace.get_tracer_provider().force_flush, timeout_millis) and all_ok

    for reader in metric_readers:
        all_ok = _force_flush_with_timeout(reader.force_flush, timeout_millis) and all_ok

    return all_ok
