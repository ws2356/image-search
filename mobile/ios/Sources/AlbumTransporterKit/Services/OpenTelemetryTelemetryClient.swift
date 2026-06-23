import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import UIKit
import Common

actor OpenTelemetryTelemetryClient: TelemetryClient {
    private static let allowedMetricAttributeKeys: Set<String> = [
        "app.route",
        "backup.flow_state",
        "permission.media_scope",
        "backup.remove_after_backup_enabled",
        "app.has_paired_desktop",
        "transfer.transport",
        "backup.failure_reason",
        "transfer.cleanup_result",
    ]

    private static var defaultRootSpanSampleRate: Double {
#if DEBUG
        1.0
#else
        0.1
#endif
    }

    private let tracerProvider: TracerProviderSdk
    private let meterProvider: MeterProviderSdk
    private let tracer: any Tracer
    private let identityProvider: LocalDeviceIdentifierProviding
    private var activeSpans: [MobileTelemetrySpan: any Span] = [:]
    private var deviceIdentity: LocalDeviceIdentifier?
    private var backupAttemptsCounter: any LongCounter
    private var backupSuccessesCounter: any LongCounter
    private var backupFailuresCounter: any LongCounter
    private var backupCompletedItemsCounter: any LongCounter

    init(
        identityProvider: LocalDeviceIdentifierProviding,
        serviceName: String = "AuBackup.iOS",
        instrumentationName: String = "AlbumTransporterKit.MobileFolder",
        instrumentationVersion: String = "0.1.0",
        serviceVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        tracesEndpoint: URL = OTLPHTTPSpanExporter.defaultTracesEndpoint,
        metricsEndpoint: URL = OTLPHTTPMetricExporter.defaultMetricsEndpoint,
        session: URLSession = .shared,
        exportTimeout: TimeInterval = 60,
        scheduleDelay: TimeInterval = 5,
        metricExportInterval: TimeInterval = 30,
        maxQueueSize: Int = 2048,
        maxExportBatchSize: Int = 128,
        rootSpanSampleRate: Double = defaultRootSpanSampleRate
    ) {
        self.identityProvider = identityProvider

        let resource = OpenTelemetryTelemetryClient.makeResource(
            serviceName: serviceName,
            serviceVersion: serviceVersion
        )
        let spanExporter = OTLPHTTPSpanExporter(
            endpoint: tracesEndpoint,
            session: session,
            timeout: exportTimeout
        )
        tracerProvider = TracerProviderBuilder()
            .with(resource: resource)
            .with(sampler: Samplers.parentBased(root: Samplers.traceIdRatio(ratio: max(0, min(rootSpanSampleRate, 1)))))
            .add(
                spanProcessor: BatchSpanProcessor(
                    spanExporter: spanExporter,
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

        let metricExporter = OTLPHTTPMetricExporter(
            endpoint: metricsEndpoint,
            session: session,
            timeout: exportTimeout
        )
        let metricReader = PeriodicMetricReaderBuilder(exporter: metricExporter)
            .setInterval(timeInterval: metricExportInterval)
            .build()
        meterProvider = MeterProviderSdk.builder()
            .setResource(resource: resource)
            .registerMetricReader(reader: metricReader)
            .registerView(
                selector: InstrumentSelector.builder()
                    .setInstrument(type: .counter)
                    .setInstrument(name: "mobile\\.backup\\..*")
                    .build(),
                view: View.builder()
                    .withAggregation(aggregation: Aggregations.sum())
                    .build()
            )
            .build()
        let meter = meterProvider.get(name: instrumentationName)
        backupAttemptsCounter = meter.counterBuilder(name: MobileTelemetryMetric.backupAttempts.rawValue)
            .build()
        backupSuccessesCounter = meter.counterBuilder(name: MobileTelemetryMetric.backupSuccesses.rawValue)
            .build()
        backupFailuresCounter = meter.counterBuilder(name: MobileTelemetryMetric.backupFailures.rawValue)
            .build()
        backupCompletedItemsCounter = meter.counterBuilder(name: MobileTelemetryMetric.backupCompletedItems.rawValue)
            .build()
    }

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        let enrichedAttributes = await enrichedAttributes(for: attributes)
        let otelAttributes = otelAttributes(for: event.rawValue, attributes: enrichedAttributes)

        if let sessionSpan = activeSpans[.backupSession] {
            sessionSpan.addEvent(name: event.rawValue, attributes: otelAttributes)
        }

        let builder = tracer
            .spanBuilder(spanName: event.rawValue)
            .setSpanKind(spanKind: .internal)
        if let parentSpan = currentParentSpan() {
            _ = builder.setParent(parentSpan.context)
        }
        let span = builder.startSpan()
        span.setAttributes(otelAttributes)
        if let status = statusForEvent(event, attributes: enrichedAttributes) {
            span.status = status
        }
        span.end()
    }

    func begin(span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) async {
        guard activeSpans[span] == nil else {
            return
        }

        let enrichedAttributes = await enrichedAttributes(for: attributes)
        let otelAttributes = otelAttributes(for: span.rawValue, attributes: enrichedAttributes)
        let builder = tracer
            .spanBuilder(spanName: span.rawValue)
            .setSpanKind(spanKind: .internal)
        if let parentSpan = parentSpan(for: span) {
            _ = builder.setParent(parentSpan.context)
        }
        let startedSpan = builder.startSpan()
        startedSpan.setAttributes(otelAttributes)
        activeSpans[span] = startedSpan

        if span != .backupSession, let sessionSpan = activeSpans[.backupSession] {
            sessionSpan.addEvent(name: "\(span.rawValue).started", attributes: otelAttributes)
        }
    }

    func end(
        span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    ) async {
        guard let activeSpan = activeSpans.removeValue(forKey: span) else {
            return
        }

        let enrichedAttributes = await enrichedAttributes(for: attributes)
        let otelAttributes = otelAttributes(for: span.rawValue, attributes: enrichedAttributes)
        activeSpan.setAttributes(otelAttributes)
        if let status {
            activeSpan.status = spanStatus(from: status)
        }
        if span != .backupSession, let sessionSpan = activeSpans[.backupSession] {
            sessionSpan.addEvent(name: "\(span.rawValue).ended", attributes: otelAttributes)
        }
        activeSpan.end()
    }

    func increment(metric: MobileTelemetryMetric, by value: Int, attributes: MobileTelemetryAttributes) async {
        let otelAttributes = otelMetricAttributes(
            attributes: filteredMetricAttributes(for: metric, attributes: attributes)
        )

        switch metric {
        case .backupAttempts:
            backupAttemptsCounter.add(value: value, attributes: otelAttributes)
        case .backupSuccesses:
            backupSuccessesCounter.add(value: value, attributes: otelAttributes)
        case .backupFailures:
            backupFailuresCounter.add(value: value, attributes: otelAttributes)
        case .backupCompletedItems:
            backupCompletedItemsCounter.add(value: value, attributes: otelAttributes)
        }
    }

    func currentTraceContext() async -> MobileTraceContext? {
        guard let parentSpan = currentParentSpan() else {
            return nil
        }

        var carrier: [String: String] = [:]
        W3CTraceContextPropagator().inject(
            spanContext: parentSpan.context,
            carrier: &carrier,
            setter: TraceContextSetter()
        )
        guard let traceParent = carrier["traceparent"], !traceParent.isEmpty else {
            return nil
        }
        return MobileTraceContext(
            traceParent: traceParent,
            traceState: carrier["tracestate"]
        )
    }

    func withSpan<T: Sendable>(
        name: String,
        attributes: MobileTelemetryAttributes,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let enrichedAttributes = await enrichedAttributes(for: attributes)
        let otelAttributes = otelAttributes(for: name, attributes: enrichedAttributes)
        let builder = tracer
            .spanBuilder(spanName: name)
            .setSpanKind(spanKind: .internal)
        if let parentSpan = currentParentSpan() {
            _ = builder.setParent(parentSpan.context)
        }
        let span = builder.startSpan()
        span.setAttributes(otelAttributes)

        do {
            let result = try await operation()
            span.status = .ok
            span.end()
            return result
        } catch {
            span.recordException(error)
            span.status = .error(description: String(describing: error))
            span.end()
            throw error
        }
    }

    func forceFlush() async {
        tracerProvider.forceFlush()
        _ = meterProvider.forceFlush()
    }

    private func parentSpan(for span: MobileTelemetrySpan) -> (any Span)? {
        if span == .backupSession {
            return nil
        }
        return currentParentSpan()
    }

    private func currentParentSpan() -> (any Span)? {
        activeSpans[.transferFlow]
            ?? activeSpans[.backupPreflight]
            ?? activeSpans[.pairingFlow]
            ?? activeSpans[.backupSession]
    }

    private func statusForEvent(
        _ event: MobileTelemetryEvent,
        attributes: MobileTelemetryAttributes
    ) -> Status? {
        switch event {
        case .pairingFailed:
            return .error(description: attributes["pairing.failure_reason"]?.stringValue ?? "pairing_failed")
        case .transferStopped:
            return .error(description: attributes["transfer.stop_reason"]?.stringValue ?? "transfer_stopped")
        default:
            return nil
        }
    }

    private func enrichedAttributes(
        for attributes: MobileTelemetryAttributes
    ) async -> MobileTelemetryAttributes {
        var mergedAttributes = attributes
        let identity = await currentDeviceIdentity()
        mergedAttributes["app.device.id"] = .string(identity.deviceUUID)
        mergedAttributes["app.install.id"] = .string(identity.installID)
        mergedAttributes["app.device.name"] = .string(identity.deviceName)
        mergedAttributes["device.model.identifier"] = .string(Self.deviceModelIdentifier())
        mergedAttributes["os.version"] = .string(ProcessInfo.processInfo.operatingSystemVersionString)
        return mergedAttributes
    }

    private func currentDeviceIdentity() async -> LocalDeviceIdentifier {
        if let deviceIdentity {
            return deviceIdentity
        }
        let resolvedIdentity = await identityProvider.currentIdentifier()
        deviceIdentity = resolvedIdentity
        return resolvedIdentity
    }

    private func otelAttributes(
        for name: String,
        attributes: MobileTelemetryAttributes
    ) -> [String: AttributeValue] {
        var otelAttributes = otelMetricAttributes(attributes: attributes)
        otelAttributes["feature.area"] = .string("mobile-folder")
        otelAttributes["telemetry.name"] = .string(name)
        return otelAttributes
    }

    private func otelMetricAttributes(
        attributes: MobileTelemetryAttributes
    ) -> [String: AttributeValue] {
        attributes.mapValues { $0.attributeValue }
    }

    private func filteredMetricAttributes(
        for metric: MobileTelemetryMetric,
        attributes: MobileTelemetryAttributes
    ) -> MobileTelemetryAttributes {
        var filteredAttributes: MobileTelemetryAttributes = [:]
        for key in Self.allowedMetricAttributeKeys {
            if let value = attributes[key] {
                filteredAttributes[key] = value
            }
        }
        switch metric {
        case .backupAttempts:
            break
        case .backupSuccesses, .backupCompletedItems:
            filteredAttributes.removeValue(forKey: "backup.failure_reason")
        case .backupFailures:
            filteredAttributes.removeValue(forKey: "transfer.cleanup_result")
        }
        return filteredAttributes
    }

    private func spanStatus(from status: MobileTelemetrySpanStatus) -> Status {
        switch status {
        case .ok:
            return .ok
        case .error(let message):
            return .error(description: message)
        }
    }

    private static func makeResource(serviceName: String, serviceVersion: String?) -> Resource {
        var attributes: [String: AttributeValue] = [
            "service.name": .string(serviceName),
            "service.namespace": .string("AuBackup"),
            "service.instance.id": .string(ProcessInfo.processInfo.globallyUniqueString),
            "deployment.environment": .string("production"),
            "app.platform": .string("ios"),
            "app.component": .string("mobile-folder"),
            "device.model.identifier": .string(deviceModelIdentifier()),
            "os.version": .string(ProcessInfo.processInfo.operatingSystemVersionString)
        ]
        if let serviceVersion, !serviceVersion.isEmpty {
            attributes["service.version"] = .string(serviceVersion)
        }
        return Resource().merging(other: Resource(attributes: attributes))
    }

    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}

private struct TraceContextSetter: Setter {
    func set(carrier: inout [String: String], key: String, value: String) {
        carrier[key] = value
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
