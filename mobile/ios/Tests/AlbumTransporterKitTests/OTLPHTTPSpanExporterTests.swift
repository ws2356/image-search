import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
@testable import AlbumTransporterKit

final class OTLPHTTPSpanExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CapturingURLProtocol.reset()
    }

    override func tearDown() {
        CapturingURLProtocol.reset()
        super.tearDown()
    }

    func test_export_posts_otlp_json_trace_payload() throws {
        let spanCaptureExporter = SpanCaptureExporter()
        let tracerProvider = TracerProviderBuilder()
            .with(
                resource: Resource(
                    attributes: [
                        "service.name": .string("AuBackup.iOS"),
                        "service.version": .string("1.2.3")
                    ]
                )
            )
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: spanCaptureExporter))
            .build()
        let tracer = tracerProvider.get(
            instrumentationName: "AlbumTransporterKit.Tests",
            instrumentationVersion: "1.2.3"
        )

        let span = tracer
            .spanBuilder(spanName: "transferCompleted")
            .setSpanKind(spanKind: .internal)
            .setAttribute(key: "event.name", value: "transferCompleted")
            .setAttribute(key: "transfer.total_count", value: 3)
            .startSpan()
        span.status = .error(description: "network_failed")
        span.end()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let exporter = OTLPHTTPSpanExporter(
            endpoint: URL(string: "https://otel.boldman.net/v1/traces")!,
            session: session,
            timeout: 1
        )
        let result = exporter.export(spans: spanCaptureExporter.exportedSpans, explicitTimeout: 1)
        guard case .success = result else {
            return XCTFail("Expected exporter to upload OTLP JSON successfully")
        }

        let request = try XCTUnwrap(CapturingURLProtocol.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://otel.boldman.net/v1/traces")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try exporter.makeRequestBody(for: spanCaptureExporter.exportedSpans)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let resourceSpans = try XCTUnwrap(payload["resourceSpans"] as? [[String: Any]])
        XCTAssertEqual(resourceSpans.count, 1)

        let resource = try XCTUnwrap(resourceSpans.first?["resource"] as? [String: Any])
        let resourceAttributes = try XCTUnwrap(resource["attributes"] as? [[String: Any]])
        XCTAssertTrue(
            resourceAttributes.contains { attribute in
                attribute["key"] as? String == "service.name" &&
                    ((attribute["value"] as? [String: Any])?["stringValue"] as? String) == "AuBackup.iOS"
            }
        )

        let scopeSpans = try XCTUnwrap(resourceSpans.first?["scopeSpans"] as? [[String: Any]])
        let scope = try XCTUnwrap(scopeSpans.first?["scope"] as? [String: Any])
        XCTAssertEqual(scope["name"] as? String, "AlbumTransporterKit.Tests")
        XCTAssertEqual(scope["version"] as? String, "1.2.3")

        let spans = try XCTUnwrap(scopeSpans.first?["spans"] as? [[String: Any]])
        let exportedSpan = try XCTUnwrap(spans.first)
        XCTAssertEqual(exportedSpan["name"] as? String, "transferCompleted")
        XCTAssertEqual(exportedSpan["kind"] as? Int, 1)
        XCTAssertEqual((exportedSpan["status"] as? [String: Any])?["code"] as? Int, 2)

        let attributes = try XCTUnwrap(exportedSpan["attributes"] as? [[String: Any]])
        XCTAssertTrue(
            attributes.contains { attribute in
                attribute["key"] as? String == "transfer.total_count" &&
                    ((attribute["value"] as? [String: Any])?["intValue"] as? String) == "3"
            }
        )
        XCTAssertEqual((exportedSpan["traceId"] as? String)?.count, 32)
        XCTAssertEqual((exportedSpan["spanId"] as? String)?.count, 16)
    }
}

private final class CapturingURLProtocol: URLProtocol {
    private static let store = CapturedRequestStore()

    static var capturedRequest: URLRequest? {
        store.request
    }

    static func reset() {
        store.request = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.store.request = request

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://otel.boldman.net/v1/traces")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CapturedRequestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedRequest
        }
        set {
            lock.lock()
            storedRequest = newValue
            lock.unlock()
        }
    }
}

private final class SpanCaptureExporter: SpanExporter, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var exportedSpans: [SpanData] = []

    @discardableResult
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        _ = explicitTimeout
        lock.lock()
        exportedSpans.append(contentsOf: spans)
        lock.unlock()
        return .success
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        _ = explicitTimeout
        return .success
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        _ = explicitTimeout
    }
}
