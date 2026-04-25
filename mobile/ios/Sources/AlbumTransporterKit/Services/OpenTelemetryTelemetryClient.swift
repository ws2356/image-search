import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

actor OpenTelemetryTelemetryClient: TelemetryClient {
    private let tracerProvider: TracerProviderSdk
    private let tracer: any Tracer

    init(
        serviceName: String = "AuBackup.iOS",
        instrumentationName: String = "AlbumTransporterKit.MobileFolder",
        instrumentationVersion: String = "0.1.0",
        serviceVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        tracesEndpoint: URL = OTLPHTTPSpanExporter.defaultTracesEndpoint,
        session: URLSession = .shared,
        exportTimeout: TimeInterval = 60,
        scheduleDelay: TimeInterval = 5,
        maxQueueSize: Int = 2048,
        maxExportBatchSize: Int = 128
    ) {
        let exporter = OTLPHTTPSpanExporter(
            endpoint: tracesEndpoint,
            session: session,
            timeout: exportTimeout
        )
        let resource = OpenTelemetryTelemetryClient.makeResource(
            serviceName: serviceName,
            serviceVersion: serviceVersion
        )
        tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .add(
                spanProcessor: BatchSpanProcessor(
                    spanExporter: exporter,
                    scheduleDelay: scheduleDelay,
                    exportTimeout: exportTimeout,
                    maxQueueSize: maxQueueSize,
                    maxExportBatchSize: maxExportBatchSize
                )
            )
            .build()

        tracer = tracerProvider.get(
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion
        )
    }

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        let span = tracer
            .spanBuilder(spanName: event.rawValue)
            .setSpanKind(spanKind: .internal)
            .startSpan()
        var spanAttributes = attributes.mapValues { $0.attributeValue }
        spanAttributes["feature.area"] = .string("mobile-folder")
        spanAttributes["event.name"] = .string(event.rawValue)
        span.setAttributes(spanAttributes)
        if event == .pairingFailed,
           let failureReason = attributes["pairing.failure_reason"]?.stringValue {
            span.status = .error(description: failureReason)
        }
        span.end()
    }

    private static func makeResource(serviceName: String, serviceVersion: String?) -> Resource {
        var attributes: [String: AttributeValue] = [
            "service.name": .string(serviceName),
            "service.namespace": .string("AuBackup"),
            "service.instance.id": .string(ProcessInfo.processInfo.globallyUniqueString),
            "deployment.environment": .string("production"),
            "app.platform": .string("ios"),
            "app.component": .string("mobile-folder")
        ]
        if let serviceVersion, !serviceVersion.isEmpty {
            attributes["service.version"] = .string(serviceVersion)
        }
        return Resource().merging(other: Resource(attributes: attributes))
    }
}

private extension MobileTelemetryAttributeValue {
    var attributeValue: AttributeValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .int(value)
        case .double(let value):
            return .double(value)
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }
}
