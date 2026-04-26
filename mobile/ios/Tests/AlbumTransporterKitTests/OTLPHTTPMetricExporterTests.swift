import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import XCTest
@testable import AlbumTransporterKit

final class OTLPHTTPMetricExporterTests: XCTestCase {
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
        let result = exporter.export(metrics: [metric])
        guard case .success = result else {
            return XCTFail("Expected metric exporter to upload OTLP JSON successfully")
        }

        let body = try exporter.makeRequestBody(for: [metric])
        let jsonString = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(jsonString.contains("\"resourceMetrics\""))
        XCTAssertTrue(jsonString.contains("\"mobile.backup.successes\""))
        XCTAssertTrue(jsonString.contains("\"aggregationTemporality\":2"))
        XCTAssertTrue(jsonString.contains("\"isMonotonic\":true"))
        XCTAssertTrue(jsonString.contains("\"asInt\":\"1\""))
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
    static func reset() {}

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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
}
