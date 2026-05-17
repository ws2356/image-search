import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
@testable import AlbumTransporterKit

final class OTLPHTTPMetricExporterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MetricCapturingURLProtocol.reset()
    }

    override func tearDown() {
        MetricCapturingURLProtocol.reset()
        super.tearDown()
    }

    func test_export_posts_otlp_json_metric_payload() throws {
        let metric = try JSONDecoder().decode(MetricData.self, from: Data(metricFixture.utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetricCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let exporter = OTLPHTTPMetricExporter(
            endpoint: URL(string: "https://otel.boldman.net/v1/metrics")!,
            session: session,
            timeout: 1
        )
        _ = exporter.export(metrics: [metric])

        let body = try exporter.makeRequestBody(for: [metric])
        let jsonString = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(jsonString.contains("\"resourceMetrics\""))
        XCTAssertTrue(jsonString.contains("\"mobile.backup.successes\""))
        XCTAssertTrue(jsonString.contains("\"aggregationTemporality\":2"))
        XCTAssertTrue(jsonString.contains("\"isMonotonic\":true"))
        XCTAssertTrue(jsonString.contains("\"asInt\":\"1\""))
        XCTAssertEqual(exporter.getAggregationTemporality(for: .counter), .cumulative)
    }

    func test_open_telemetry_client_force_flush_posts_metric_request() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MetricCapturingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let telemetryClient = OpenTelemetryTelemetryClient(
            identityProvider: StaticMetricIdentityProvider(),
            tracesEndpoint: URL(string: "https://otel.boldman.net/v1/traces")!,
            metricsEndpoint: URL(string: "https://otel.boldman.net/v1/metrics")!,
            session: session,
            scheduleDelay: 60,
            metricExportInterval: 60
        )

        await telemetryClient.increment(
            metric: MobileTelemetryMetric.backupSuccesses,
            by: 1,
            attributes: [
                "correlation.session_id": MobileTelemetryAttributeValue.string("pairing-demo-001"),
                "app.device.id": MobileTelemetryAttributeValue.string("ios-device-001"),
                "transfer.transferred_count": MobileTelemetryAttributeValue.int(42),
                "transfer.transport": MobileTelemetryAttributeValue.string("lan"),
                "transfer.cleanup_result": MobileTelemetryAttributeValue.string("removed"),
            ]
        )
        await telemetryClient.forceFlush()

        let payloads = MetricCapturingURLProtocol.capturedRequestBodies()
        let metricPayload = try XCTUnwrap(
            payloads.last(where: { body in
                String(data: body, encoding: .utf8)?.contains("\"mobile.backup.successes\"") == true
            })
        )
        let bodyData = metricPayload
        let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertTrue(bodyString.contains("\"mobile.backup.successes\""))
        XCTAssertTrue(bodyString.contains("\"lan\""))
        XCTAssertTrue(bodyString.contains("\"removed\""))
        XCTAssertFalse(bodyString.contains("\"pairing-demo-001\""))
        XCTAssertFalse(bodyString.contains("\"ios-device-001\""))
        XCTAssertFalse(bodyString.contains("\"42\""))
        XCTAssertTrue(bodyString.contains("\"service.name\""))
        XCTAssertTrue(bodyString.contains("\"AuBackup.iOS\""))
    }

    private var metricFixture: String {
        #"""
        {
          "resource": {
            "attributes": {
              "service.name": {
                "string": {
                  "_0": "AuBackup.iOS"
                }
              }
            }
          },
          "instrumentationScopeInfo": {
            "name": "AlbumTransporterKit.Tests"
          },
          "name": "mobile.backup.successes",
          "description": "Successful backup counter",
          "unit": "1",
          "type": {
            "LongSum": {}
          },
          "isMonotonic": true,
          "dataPoints": [
            {
              "value": 1,
              "startEpochNanos": 1,
              "endEpochNanos": 2,
              "attributes": {
                "app.device.id": {
                  "string": {
                    "_0": "device-123"
                  }
                }
              },
              "exemplars": []
            }
          ],
          "aggregationTemporality": {
            "cumulative": {}
          }
        }
        """#
    }
}

private final class MetricCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var capturedBodies: [Data] = []

    static func reset() {
        capturedBodies = []
    }

    static func capturedRequestBodies() -> [Data] {
        capturedBodies
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedBodies.append(Self.requestBodyData(for: request) ?? Data())
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://otel.boldman.net/v1/metrics")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var body = Data()
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            guard bytesRead > 0 else {
                break
            }
            body.append(buffer, count: bytesRead)
        }
        return body
    }
}

private struct StaticMetricIdentityProvider: LocalDeviceIdentityProviding {
    func currentIdentity() async -> LocalDeviceIdentity {
        LocalDeviceIdentity(
            installID: "install-001",
            deviceUUID: "ios-device-001",
            deviceName: "Test iPhone",
            platform: "ios"
        )
    }
}
