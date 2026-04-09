import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import StdoutExporter

actor OpenTelemetryTelemetryClient: TelemetryClient {
    private let tracer: any Tracer

    init(
        instrumentationName: String = "AlbumTransporterKit.MobileFolder",
        instrumentationVersion: String = "0.1.0"
    ) {
        let exporter = StdoutSpanExporter()
        let tracerProvider = TracerProviderBuilder()
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter))
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
        tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion
        )
    }

    func record(event: MobileTelemetryEvent) async {
        let span = tracer.spanBuilder(spanName: event.rawValue).startSpan()
        span.setAttribute(key: "feature.area", value: "mobile-folder")
        span.setAttribute(key: "event.name", value: event.rawValue)
        span.end()
    }
}
