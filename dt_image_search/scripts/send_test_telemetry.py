import argparse
import logging
import os
import sys
import time

project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider, Meter
from opentelemetry.sdk.metrics.export import AggregationTemporality, ConsoleMetricExporter, PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider, Tracer
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter

from dt_image_search.telemetry.otlp_settings import EXPORT_BATCH_SIZE, EXPORT_QUEUE_SIZE, EXPORT_TIMEOUT_SECONDS, LOGS_UPLOAD_ENDPOINT, METRICS_UPLOAD_ENDPOINT, TRACES_UPLOAD_ENDPOINT


TEST_SERVICE_NAME = "imagesearch_telemetry_test"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send test log, trace, and metric records to the configured OTLP backend."
    )
    parser.add_argument(
        "--message",
        default="Manual telemetry connectivity test",
        help="Base message to include in the emitted telemetry.",
    )
    parser.add_argument(
        "--service-name",
        default=TEST_SERVICE_NAME,
        help="Override the service.name used by the test telemetry events.",
    )
    return parser.parse_args()


def build_resource(service_name: str) -> Resource:
    return Resource.create(
        attributes={
            "service.name": service_name,
        }
    )


def create_meter_provider(resource: Resource) -> tuple[MeterProvider, Meter]:
    temporality = {
        Counter: AggregationTemporality.DELTA,
        UpDownCounter: AggregationTemporality.CUMULATIVE,
        Histogram: AggregationTemporality.DELTA,
        ObservableCounter: AggregationTemporality.DELTA,
        ObservableUpDownCounter: AggregationTemporality.CUMULATIVE,
        ObservableGauge: AggregationTemporality.CUMULATIVE,
    }
    metric_exporter = OTLPMetricExporter(
        endpoint=METRICS_UPLOAD_ENDPOINT,
        preferred_temporality=temporality,
        timeout=EXPORT_TIMEOUT_SECONDS,
    )
    readers = [PeriodicExportingMetricReader(metric_exporter, export_interval_millis=60_000)]
    if sys.stdout is not None and sys.stderr is not None:
        readers.append(
            PeriodicExportingMetricReader(
                ConsoleMetricExporter(preferred_temporality=temporality),
                export_interval_millis=60_000,
            )
        )
    provider = MeterProvider(metric_readers=readers, resource=resource)
    meter = provider.get_meter(TEST_SERVICE_NAME)
    return provider, meter


def create_tracer_provider(resource: Resource) -> tuple[TracerProvider, Tracer]:
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(
        BatchSpanProcessor(
            OTLPSpanExporter(endpoint=TRACES_UPLOAD_ENDPOINT, timeout=EXPORT_TIMEOUT_SECONDS),
            schedule_delay_millis=60_000,
            max_export_batch_size=EXPORT_BATCH_SIZE,
            max_queue_size=EXPORT_QUEUE_SIZE,
        )
    )
    if sys.stdout is not None and sys.stderr is not None:
        provider.add_span_processor(
            BatchSpanProcessor(
                ConsoleSpanExporter(),
                schedule_delay_millis=60_000,
                max_export_batch_size=EXPORT_BATCH_SIZE,
                max_queue_size=EXPORT_QUEUE_SIZE,
            )
        )
    return provider, provider.get_tracer(TEST_SERVICE_NAME)


def create_logger(resource: Resource) -> tuple[LoggerProvider, logging.Logger]:
    provider = LoggerProvider(resource=resource)
    provider.add_log_record_processor(
        BatchLogRecordProcessor(
            OTLPLogExporter(endpoint=LOGS_UPLOAD_ENDPOINT, timeout=EXPORT_TIMEOUT_SECONDS),
            schedule_delay_millis=60_000,
            max_export_batch_size=EXPORT_BATCH_SIZE,
            max_queue_size=EXPORT_QUEUE_SIZE,
        )
    )
    logger = logging.getLogger(TEST_SERVICE_NAME)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    logger.handlers.clear()
    logger.addHandler(LoggingHandler(level=logging.INFO, logger_provider=provider))
    return provider, logger


def flush_all(logger_provider: LoggerProvider, tracer_provider: TracerProvider, meter_provider: MeterProvider) -> None:
    logger_provider.force_flush()
    tracer_provider.force_flush()
    meter_provider.force_flush()


from opentelemetry.sdk.metrics import Counter, Histogram, ObservableCounter, ObservableGauge, ObservableUpDownCounter, UpDownCounter


def main() -> int:
    args = parse_args()
    timestamp = int(time.time())
    resource = build_resource(args.service_name)
    meter_provider, meter = create_meter_provider(resource)
    tracer_provider, tracer = create_tracer_provider(resource)
    logger_provider, logger = create_logger(resource)
    test_counter = meter.create_counter("test_counter")
    test_counter.add(1)

    with tracer.start_as_current_span("test_trace") as span:
        span.set_attribute("test_message", args.message)
        span.set_attribute("timestamp", timestamp)
        logger.info(
            "telemetry_test at %s: %s @ %s",
            __file__,
            args.message,
            timestamp,
        )

    flush_all(logger_provider, tracer_provider, meter_provider)
    print(
        "Sent test telemetry "
        f"(service_name={args.service_name}, timestamp={timestamp})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())