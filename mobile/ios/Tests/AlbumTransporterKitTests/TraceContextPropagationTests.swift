import Foundation
import XCTest
@testable import AlbumTransporterKit

final class TraceContextPropagationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TraceContextCapturingURLProtocol.reset()
    }

    override func tearDown() {
        TraceContextCapturingURLProtocol.reset()
        super.tearDown()
    }

    func test_pairing_bootstrap_client_includes_trace_context_in_request_body() async throws {
        TraceContextCapturingURLProtocol.responseData = acceptedPairingResponseData()
        let client = URLSessionPairingBootstrapClient(
            session: makeSession(),
            telemetryClient: StaticTraceContextTelemetryClient()
        )

        _ = try await client.claimPairing(
            at: PairingQRCodePayload.demo.bootstrapURL,
            request: PairingClaimRequest(
                sessionID: "pairing-demo-001",
                oneTimePasscode: "482913",
                platform: "ios",
                deviceUUID: "ios-device-001",
                deviceName: "Alice iPhone",
                installID: "install-001",
                clientNonce: "client-nonce-001"
            )
        )

        let requestBody = try XCTUnwrap(TraceContextCapturingURLProtocol.capturedJSONObject)
        XCTAssertEqual(requestBody["traceparent"] as? String, StaticTraceContextTelemetryClient.traceParent)
        XCTAssertEqual(requestBody["tracestate"] as? String, StaticTraceContextTelemetryClient.traceState)
    }

    func test_transfer_client_includes_trace_context_in_start_request_body() async throws {
        TraceContextCapturingURLProtocol.responseData = acceptedTransferResponseData()
        let client = URLSessionMobileTransferClient(
            session: makeSession(),
            telemetryClient: StaticTraceContextTelemetryClient()
        )

        try await client.startSession(
            desktop: TrustedDesktopRecord(
                desktopDeviceID: "desktop-device-001",
                desktopName: "Studio Mac",
                endpointURL: URL(string: "http://127.0.0.1:38933/api/mobile/pairing/claim")!,
                mobileDeviceUUID: "ios-device-001",
                sharedKeyBase64: "shared-key-001",
                transport: .lan,
                lastSessionID: "pairing-demo-001",
                pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
            ),
            totalAssets: 3
        )

        let requestBody = try XCTUnwrap(TraceContextCapturingURLProtocol.capturedJSONObject)
        XCTAssertEqual(requestBody["traceparent"] as? String, StaticTraceContextTelemetryClient.traceParent)
        XCTAssertEqual(requestBody["tracestate"] as? String, StaticTraceContextTelemetryClient.traceState)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraceContextCapturingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func acceptedPairingResponseData() -> Data {
        """
        {
          "schema": "dtis.mobile-pairing.v1",
          "status": "accepted",
          "backup_state": "pairing_completed",
          "message": "Pairing accepted.",
          "session_id": "pairing-demo-001",
          "desktop_device_id": "desktop-device-001",
          "desktop_name": "Studio Mac",
          "device_uuid": "ios-device-001",
          "folder_id": 1,
          "folder_path": "/Users/demo/Alice iPhone",
          "transport": "lan",
          "paired_at": "2026-04-10T16:23:04+00:00",
          "server_nonce": "server-nonce-001"
        }
        """.data(using: .utf8)!
    }

    private func acceptedTransferResponseData() -> Data {
        """
        {
          "schema": "dtis.mobile-transfer.v1",
          "status": "accepted",
          "message": "Desktop is ready to receive assets.",
          "session_id": "pairing-demo-001",
          "device_uuid": "ios-device-001",
          "total_assets": 3
        }
        """.data(using: .utf8)!
    }
}

private struct StaticTraceContextTelemetryClient: TelemetryClient {
    static let traceParent = "00-ff000000000000000000000000000041-ff00000000000041-01"
    static let traceState = "foo=bar"

    func currentTraceContext() async -> MobileTraceContext? {
        MobileTraceContext(traceParent: Self.traceParent, traceState: Self.traceState)
    }
}

private final class TraceContextCapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var capturedJSONObject: [String: Any]?

    static func reset() {
        responseData = Data()
        capturedJSONObject = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let body = Self.requestBodyData(for: request),
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            Self.capturedJSONObject = object
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
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

        let bufferSize = 4 * 1024
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}
