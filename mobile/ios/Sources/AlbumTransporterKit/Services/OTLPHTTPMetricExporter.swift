import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

final class OTLPHTTPMetricExporter: MetricExporter, @unchecked Sendable {
    static let defaultMetricsEndpoint = URL(string: "https://otel.boldman.net/v1/metrics")!

    private let endpoint: URL
    private let session: URLSession
    private let timeout: TimeInterval
    private let requestStore: PersistentOTLPRequestStore

    init(
        endpoint: URL = defaultMetricsEndpoint,
        session: URLSession = .shared,
        timeout: TimeInterval = 60,
        requestStore: PersistentOTLPRequestStore = PersistentOTLPRequestStore(signal: "metrics")
    ) {
        self.endpoint = endpoint
        self.session = session
        self.timeout = timeout
        self.requestStore = requestStore
    }

    func export(metrics: [MetricData]) -> ExportResult {
        guard !metrics.isEmpty else {
            return .success
        }

        let requestBody: Data
        do {
            requestBody = try makeRequestBody(for: metrics)
        } catch {
            return .failure
        }

        guard requestStore.enqueue(payload: requestBody) else {
            return .failure
        }

        return requestStore.drain { [self] payload in
            send(payload: payload, timeout: timeout)
        } ? .success : .failure
    }

    func flush() -> ExportResult {
        requestStore.drain { [self] payload in
            send(payload: payload, timeout: timeout)
        } ? .success : .failure
    }

    func shutdown() -> ExportResult {
        flush()
    }

    func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality {
        .cumulative
    }

    func makeRequestBody(for metrics: [MetricData]) throws -> Data {
        let payload = ExportMetricsServiceRequest(resourceMetrics: resourceMetricsPayload(from: metrics))
        return try JSONEncoder().encode(payload)
    }

    private func send(payload: Data, timeout: TimeInterval) -> Bool {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let semaphore = DispatchSemaphore(value: 0)
        let requestState = HTTPMetricExportRequestState()

        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }

            guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                return
            }

            requestState.setDidSucceed((200 ..< 300).contains(httpResponse.statusCode))
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            return false
        }

        return requestState.didSucceed
    }

    private func resourceMetricsPayload(from metrics: [MetricData]) -> [ResourceMetricsPayload] {
        Dictionary(grouping: metrics, by: \.resource).map { resource, resourceMetrics in
            let scopeMetrics = Dictionary(grouping: resourceMetrics, by: \.instrumentationScopeInfo).map { scope, scopedMetrics in
                ScopeMetricsPayload(
                    scope: MetricInstrumentationScopePayload(
                        name: scope.name.isEmpty ? nil : scope.name,
                        version: scope.version,
                        attributes: keyValuePayloads(from: scope.attributes ?? [:]).nilIfEmpty
                    ),
                    metrics: scopedMetrics.compactMap(metricPayload(from:))
                )
            }

            return ResourceMetricsPayload(
                resource: MetricResourcePayload(attributes: keyValuePayloads(from: resource.attributes)),
                scopeMetrics: scopeMetrics
            )
        }
    }

    private func metricPayload(from metric: MetricData) -> MetricPayload? {
        switch metric.type {
        case .LongSum:
            let points = metric.data.points.compactMap { point -> SumDataPointPayload? in
                guard let point = point as? LongPointData else {
                    return nil
                }
                return SumDataPointPayload(
                    attributes: keyValuePayloads(from: point.attributes).nilIfEmpty,
                    startTimeUnixNano: String(point.startEpochNanos),
                    timeUnixNano: String(point.endEpochNanos),
                    asInt: String(point.value),
                    asDouble: nil
                )
            }
            return MetricPayload(
                name: metric.name,
                description: metric.description,
                unit: metric.unit,
                sum: SumPayload(
                    aggregationTemporality: otlpAggregationTemporality(metric.data.aggregationTemporality),
                    isMonotonic: metric.isMonotonic,
                    dataPoints: points
                )
            )
        case .DoubleSum:
            let points = metric.data.points.compactMap { point -> SumDataPointPayload? in
                guard let point = point as? DoublePointData else {
                    return nil
                }
                return SumDataPointPayload(
                    attributes: keyValuePayloads(from: point.attributes).nilIfEmpty,
                    startTimeUnixNano: String(point.startEpochNanos),
                    timeUnixNano: String(point.endEpochNanos),
                    asInt: nil,
                    asDouble: point.value
                )
            }
            return MetricPayload(
                name: metric.name,
                description: metric.description,
                unit: metric.unit,
                sum: SumPayload(
                    aggregationTemporality: otlpAggregationTemporality(metric.data.aggregationTemporality),
                    isMonotonic: metric.isMonotonic,
                    dataPoints: points
                )
            )
        default:
            return nil
        }
    }

    private func otlpAggregationTemporality(_ temporality: AggregationTemporality) -> Int {
        switch temporality {
        case .delta:
            return 1
        case .cumulative:
            return 2
        }
    }

    private func keyValuePayloads(from attributes: [String: AttributeValue]) -> [MetricKeyValuePayload] {
        attributes
            .sorted { $0.key < $1.key }
            .map { MetricKeyValuePayload(key: $0.key, value: anyValuePayload(from: $0.value)) }
    }

    private func anyValuePayload(from value: AttributeValue) -> MetricAnyValuePayload {
        switch value {
        case .string(let stringValue):
            return MetricAnyValuePayload(stringValue: stringValue)
        case .bool(let boolValue):
            return MetricAnyValuePayload(boolValue: boolValue)
        case .int(let intValue):
            return MetricAnyValuePayload(intValue: String(intValue))
        case .double(let doubleValue):
            return MetricAnyValuePayload(doubleValue: doubleValue)
        case .array(let arrayValue):
            return MetricAnyValuePayload(
                arrayValue: MetricArrayValuePayload(values: arrayValue.values.map(anyValuePayload(from:)))
            )
        case .set(let setValue):
            return MetricAnyValuePayload(
                kvlistValue: MetricKeyValueListPayload(values: keyValuePayloads(from: setValue.labels))
            )
        case .stringArray(let stringValues):
            return MetricAnyValuePayload(
                arrayValue: MetricArrayValuePayload(values: stringValues.map { MetricAnyValuePayload(stringValue: $0) })
            )
        case .boolArray(let boolValues):
            return MetricAnyValuePayload(
                arrayValue: MetricArrayValuePayload(values: boolValues.map { MetricAnyValuePayload(boolValue: $0) })
            )
        case .intArray(let intValues):
            return MetricAnyValuePayload(
                arrayValue: MetricArrayValuePayload(values: intValues.map { MetricAnyValuePayload(intValue: String($0)) })
            )
        case .doubleArray(let doubleValues):
            return MetricAnyValuePayload(
                arrayValue: MetricArrayValuePayload(values: doubleValues.map { MetricAnyValuePayload(doubleValue: $0) })
            )
        }
    }
}

private struct ExportMetricsServiceRequest: Encodable {
    let resourceMetrics: [ResourceMetricsPayload]
}

private struct ResourceMetricsPayload: Encodable {
    let resource: MetricResourcePayload
    let scopeMetrics: [ScopeMetricsPayload]
}

private struct MetricResourcePayload: Encodable {
    let attributes: [MetricKeyValuePayload]
}

private struct ScopeMetricsPayload: Encodable {
    let scope: MetricInstrumentationScopePayload
    let metrics: [MetricPayload]
}

private struct MetricInstrumentationScopePayload: Encodable {
    let name: String?
    let version: String?
    let attributes: [MetricKeyValuePayload]?
}

private struct MetricPayload: Encodable {
    let name: String
    let description: String
    let unit: String
    let sum: SumPayload?
}

private struct SumPayload: Encodable {
    let aggregationTemporality: Int
    let isMonotonic: Bool
    let dataPoints: [SumDataPointPayload]
}

private struct SumDataPointPayload: Encodable {
    let attributes: [MetricKeyValuePayload]?
    let startTimeUnixNano: String
    let timeUnixNano: String
    let asInt: String?
    let asDouble: Double?
}

private struct MetricKeyValuePayload: Encodable {
    let key: String
    let value: MetricAnyValuePayload
}

private struct MetricAnyValuePayload: Encodable {
    let stringValue: String?
    let boolValue: Bool?
    let intValue: String?
    let doubleValue: Double?
    let arrayValue: MetricArrayValuePayload?
    let kvlistValue: MetricKeyValueListPayload?

    init(
        stringValue: String? = nil,
        boolValue: Bool? = nil,
        intValue: String? = nil,
        doubleValue: Double? = nil,
        arrayValue: MetricArrayValuePayload? = nil,
        kvlistValue: MetricKeyValueListPayload? = nil
    ) {
        self.stringValue = stringValue
        self.boolValue = boolValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.arrayValue = arrayValue
        self.kvlistValue = kvlistValue
    }
}

private struct MetricArrayValuePayload: Encodable {
    let values: [MetricAnyValuePayload]
}

private struct MetricKeyValueListPayload: Encodable {
    let values: [MetricKeyValuePayload]
}

private final class HTTPMetricExportRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDidSucceed = false

    var didSucceed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedDidSucceed
    }

    func setDidSucceed(_ didSucceed: Bool) {
        lock.lock()
        storedDidSucceed = didSucceed
        lock.unlock()
    }
}

private extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
