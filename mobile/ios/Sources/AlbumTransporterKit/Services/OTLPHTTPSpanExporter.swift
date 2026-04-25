import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

final class OTLPHTTPSpanExporter: SpanExporter, @unchecked Sendable {
    static let defaultTracesEndpoint = URL(string: "https://otel.boldman.net/v1/traces")!

    private let endpoint: URL
    private let session: URLSession
    private let timeout: TimeInterval

    init(
        endpoint: URL = defaultTracesEndpoint,
        session: URLSession = .shared,
        timeout: TimeInterval = 60
    ) {
        self.endpoint = endpoint
        self.session = session
        self.timeout = timeout
    }

    @discardableResult
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        guard !spans.isEmpty else {
            return .success
        }

        let requestBody: Data
        do {
            requestBody = try makeRequestBody(for: spans)
        } catch {
            return .failure
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = explicitTimeout ?? timeout

        let semaphore = DispatchSemaphore(value: 0)
        let requestTimeout = explicitTimeout ?? timeout
        let requestState = HTTPExportRequestState()

        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }

            guard error == nil, let httpResponse = response as? HTTPURLResponse else {
                return
            }

            requestState.setDidSucceed((200 ..< 300).contains(httpResponse.statusCode))
        }
        task.resume()

        if semaphore.wait(timeout: .now() + requestTimeout) == .timedOut {
            task.cancel()
            return .failure
        }

        return requestState.didSucceed ? .success : .failure
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {}

    func makeRequestBody(for spans: [SpanData]) throws -> Data {
        let payload = ExportTraceServiceRequest(resourceSpans: resourceSpansPayload(from: spans))
        return try JSONEncoder().encode(payload)
    }

    private func resourceSpansPayload(from spans: [SpanData]) -> [ResourceSpansPayload] {
        Dictionary(grouping: spans, by: \.resource).map { resource, resourceSpans in
            let scopeSpans = Dictionary(grouping: resourceSpans, by: \.instrumentationScope).map { scope, scopedSpans in
                ScopeSpansPayload(
                    scope: instrumentationScopePayload(from: scope),
                    spans: scopedSpans.map(spanPayload(from:))
                )
            }

            return ResourceSpansPayload(
                resource: ResourcePayload(attributes: keyValuePayloads(from: resource.attributes)),
                scopeSpans: scopeSpans
            )
        }
    }

    private func instrumentationScopePayload(from scope: InstrumentationScopeInfo) -> InstrumentationScopePayload {
        InstrumentationScopePayload(
            name: scope.name.isEmpty ? nil : scope.name,
            version: scope.version,
            attributes: keyValuePayloads(from: scope.attributes ?? [:]).nilIfEmpty
        )
    }

    private func spanPayload(from span: SpanData) -> SpanPayload {
        SpanPayload(
            traceId: span.traceId.hexString.uppercased(),
            spanId: span.spanId.hexString.uppercased(),
            traceState: traceStateString(from: span.traceState),
            parentSpanId: span.parentSpanId?.hexString.uppercased(),
            flags: spanFlags(for: span),
            name: span.name,
            kind: otlpSpanKind(for: span.kind),
            startTimeUnixNano: unixTimeNanosecondsString(for: span.startTime),
            endTimeUnixNano: unixTimeNanosecondsString(for: span.endTime),
            attributes: keyValuePayloads(from: span.attributes).nilIfEmpty,
            droppedAttributesCount: droppedCount(recorded: span.totalAttributeCount, retained: span.attributes.count),
            events: span.events.map(spanEventPayload(from:)).nilIfEmpty,
            droppedEventsCount: droppedCount(recorded: span.totalRecordedEvents, retained: span.events.count),
            links: span.links.map(spanLinkPayload(from:)).nilIfEmpty,
            droppedLinksCount: droppedCount(recorded: span.totalRecordedLinks, retained: span.links.count),
            status: statusPayload(from: span.status)
        )
    }

    private func spanEventPayload(from event: SpanData.Event) -> SpanEventPayload {
        SpanEventPayload(
            timeUnixNano: unixTimeNanosecondsString(for: event.timestamp),
            name: event.name,
            attributes: keyValuePayloads(from: event.attributes).nilIfEmpty
        )
    }

    private func spanLinkPayload(from link: SpanData.Link) -> SpanLinkPayload {
        SpanLinkPayload(
            traceId: link.context.traceId.hexString.uppercased(),
            spanId: link.context.spanId.hexString.uppercased(),
            traceState: traceStateString(from: link.context.traceState),
            attributes: keyValuePayloads(from: link.attributes).nilIfEmpty,
            flags: UInt32(link.context.traceFlags.byte)
        )
    }

    private func statusPayload(from status: Status) -> StatusPayload? {
        switch status {
        case .unset:
            return nil
        case .ok:
            return StatusPayload(message: nil, code: 1)
        case .error(let description):
            return StatusPayload(message: description.isEmpty ? nil : description, code: 2)
        }
    }

    private func spanFlags(for span: SpanData) -> UInt32? {
        var flags = UInt32(span.traceFlags.byte)
        if span.parentSpanId != nil {
            flags |= 0x00000100
            if span.hasRemoteParent {
                flags |= 0x00000200
            }
        }
        return flags == 0 ? nil : flags
    }

    private func traceStateString(from traceState: TraceState) -> String? {
        guard !traceState.entries.isEmpty else {
            return nil
        }
        return traceState.entries.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    private func unixTimeNanosecondsString(for date: Date) -> String {
        String(UInt64(max(0, date.timeIntervalSince1970 * 1_000_000_000)))
    }

    private func droppedCount(recorded: Int, retained: Int) -> Int? {
        let count = max(recorded - retained, 0)
        return count == 0 ? nil : count
    }

    private func otlpSpanKind(for kind: SpanKind) -> Int {
        switch kind {
        case .internal:
            return 1
        case .server:
            return 2
        case .client:
            return 3
        case .producer:
            return 4
        case .consumer:
            return 5
        }
    }

    private func keyValuePayloads(from attributes: [String: AttributeValue]) -> [KeyValuePayload] {
        attributes
            .sorted { $0.key < $1.key }
            .map { KeyValuePayload(key: $0.key, value: anyValuePayload(from: $0.value)) }
    }

    private func anyValuePayload(from value: AttributeValue) -> AnyValuePayload {
        switch value {
        case .string(let stringValue):
            return AnyValuePayload(stringValue: stringValue)
        case .bool(let boolValue):
            return AnyValuePayload(boolValue: boolValue)
        case .int(let intValue):
            return AnyValuePayload(intValue: String(intValue))
        case .double(let doubleValue):
            return AnyValuePayload(doubleValue: doubleValue)
        case .array(let arrayValue):
            return AnyValuePayload(
                arrayValue: ArrayValuePayload(values: arrayValue.values.map(anyValuePayload(from:)))
            )
        case .set(let setValue):
            return AnyValuePayload(
                kvlistValue: KeyValueListPayload(values: keyValuePayloads(from: setValue.labels))
            )
        case .stringArray(let stringValues):
            return AnyValuePayload(
                arrayValue: ArrayValuePayload(values: stringValues.map { AnyValuePayload(stringValue: $0) })
            )
        case .boolArray(let boolValues):
            return AnyValuePayload(
                arrayValue: ArrayValuePayload(values: boolValues.map { AnyValuePayload(boolValue: $0) })
            )
        case .intArray(let intValues):
            return AnyValuePayload(
                arrayValue: ArrayValuePayload(values: intValues.map { AnyValuePayload(intValue: String($0)) })
            )
        case .doubleArray(let doubleValues):
            return AnyValuePayload(
                arrayValue: ArrayValuePayload(values: doubleValues.map { AnyValuePayload(doubleValue: $0) })
            )
        }
    }
}

private struct ExportTraceServiceRequest: Encodable {
    let resourceSpans: [ResourceSpansPayload]
}

private struct ResourceSpansPayload: Encodable {
    let resource: ResourcePayload
    let scopeSpans: [ScopeSpansPayload]
}

private struct ResourcePayload: Encodable {
    let attributes: [KeyValuePayload]
}

private struct ScopeSpansPayload: Encodable {
    let scope: InstrumentationScopePayload
    let spans: [SpanPayload]
}

private struct InstrumentationScopePayload: Encodable {
    let name: String?
    let version: String?
    let attributes: [KeyValuePayload]?
}

private struct SpanPayload: Encodable {
    let traceId: String
    let spanId: String
    let traceState: String?
    let parentSpanId: String?
    let flags: UInt32?
    let name: String
    let kind: Int
    let startTimeUnixNano: String
    let endTimeUnixNano: String
    let attributes: [KeyValuePayload]?
    let droppedAttributesCount: Int?
    let events: [SpanEventPayload]?
    let droppedEventsCount: Int?
    let links: [SpanLinkPayload]?
    let droppedLinksCount: Int?
    let status: StatusPayload?
}

private struct SpanEventPayload: Encodable {
    let timeUnixNano: String
    let name: String
    let attributes: [KeyValuePayload]?
}

private struct SpanLinkPayload: Encodable {
    let traceId: String
    let spanId: String
    let traceState: String?
    let attributes: [KeyValuePayload]?
    let flags: UInt32
}

private struct StatusPayload: Encodable {
    let message: String?
    let code: Int
}

private struct KeyValuePayload: Encodable {
    let key: String
    let value: AnyValuePayload
}

private struct AnyValuePayload: Encodable {
    let stringValue: String?
    let boolValue: Bool?
    let intValue: String?
    let doubleValue: Double?
    let arrayValue: ArrayValuePayload?
    let kvlistValue: KeyValueListPayload?

    init(
        stringValue: String? = nil,
        boolValue: Bool? = nil,
        intValue: String? = nil,
        doubleValue: Double? = nil,
        arrayValue: ArrayValuePayload? = nil,
        kvlistValue: KeyValueListPayload? = nil
    ) {
        self.stringValue = stringValue
        self.boolValue = boolValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.arrayValue = arrayValue
        self.kvlistValue = kvlistValue
    }
}

private struct ArrayValuePayload: Encodable {
    let values: [AnyValuePayload]
}

private struct KeyValueListPayload: Encodable {
    let values: [KeyValuePayload]
}

private extension Array {
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}

private final class HTTPExportRequestState: @unchecked Sendable {
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
