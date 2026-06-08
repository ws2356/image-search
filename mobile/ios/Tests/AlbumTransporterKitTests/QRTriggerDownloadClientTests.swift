import XCTest

@testable import AlbumTransporterKit

final class QRTriggerDownloadClientTests: XCTestCase {
    private var client: QRTriggerDownloadClient!
    private var urlSession: URLSession!

    override func tearDown() {
        client = nil
        urlSession = nil
        super.tearDown()
    }

    func testClaimTextSuccess() async throws {
        let expectedText = "Hello from Mac!"
        let config = URLProtocolMock.config(
            statusCode: 200,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: expectedText.data(using: .utf8)!
        )
        URLProtocolMock.requestHandler = { _ in
            return config
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        let result = try await client.claim(
            hosts: ["192.168.1.10"],
            port: 9527,
            stashId: "test-stash-id",
            optCode: "123456"
        )

        switch result {
        case .text(let text):
            XCTAssertEqual(text, expectedText)
        case .image:
            XCTFail("Expected text result but got image")
        }
    }

    func testClaimImageSuccess() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic bytes
        let config = URLProtocolMock.config(
            statusCode: 200,
            headers: [
                "Content-Type": "image/png",
                "X-Original-Filename": "photo.png",
            ],
            body: imageData
        )
        URLProtocolMock.requestHandler = { _ in
            return config
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        let result = try await client.claim(
            hosts: ["192.168.1.10"],
            port: 9527,
            stashId: "test-stash-id",
            optCode: "123456"
        )

        switch result {
        case .text:
            XCTFail("Expected image result but got text")
        case .image(let data, let contentType, let filename):
            XCTAssertEqual(data, imageData)
            XCTAssertEqual(contentType, "image/png")
            XCTAssertEqual(filename, "photo.png")
        }
    }

    func testClaimInvalidOptCode() async {
        let config = URLProtocolMock.config(
            statusCode: 401,
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"Invalid opt-code\"}".utf8)
        )
        URLProtocolMock.requestHandler = { _ in
            return config
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        do {
            _ = try await client.claim(
                hosts: ["192.168.1.10"],
                port: 9527,
                stashId: "test-stash-id",
                optCode: "wrong"
            )
            XCTFail("Expected invalidOptCode error")
        } catch let error as QRTriggerDownloadClientError {
            if case .invalidOptCode = error {
                // expected
            } else {
                XCTFail("Expected invalidOptCode but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClaimStashExpired() async {
        let config = URLProtocolMock.config(
            statusCode: 410,
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"Stash has expired\"}".utf8)
        )
        URLProtocolMock.requestHandler = { _ in
            return config
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        do {
            _ = try await client.claim(
                hosts: ["192.168.1.10"],
                port: 9527,
                stashId: "test-stash-id",
                optCode: "123456"
            )
            XCTFail("Expected stashExpired error")
        } catch let error as QRTriggerDownloadClientError {
            if case .stashExpired = error {
                // expected
            } else {
                XCTFail("Expected stashExpired but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClaimStashNotFound() async {
        let config = URLProtocolMock.config(
            statusCode: 404,
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"Stash not found\"}".utf8)
        )
        URLProtocolMock.requestHandler = { _ in
            return config
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        do {
            _ = try await client.claim(
                hosts: ["192.168.1.10"],
                port: 9527,
                stashId: "nonexistent",
                optCode: "123456"
            )
            XCTFail("Expected stashNotFound error")
        } catch let error as QRTriggerDownloadClientError {
            if case .stashNotFound = error {
                // expected
            } else {
                XCTFail("Expected stashNotFound but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClaimServerError() async {
        let config = URLProtocolMock.config(
            statusCode: 500,
            headers: ["Content-Type": "application/json"],
            body: Data("{\"error\":\"Internal error\"}".utf8)
        )
        URLProtocolMock.requestHandler = { _ in
            return config
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        do {
            _ = try await client.claim(
                hosts: ["192.168.1.10"],
                port: 9527,
                stashId: "test-stash-id",
                optCode: "123456"
            )
            XCTFail("Expected serverError")
        } catch let error as QRTriggerDownloadClientError {
            if case .serverError = error {
                // expected
            } else {
                XCTFail("Expected serverError but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClaimFailoverAllHostsFail() async {
        var callCount = 0
        URLProtocolMock.requestHandler = { _ in
            callCount += 1
            throw URLError(.cannotConnectToHost)
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        do {
            _ = try await client.claim(
                hosts: ["192.168.1.10", "192.168.1.11"],
                port: 9527,
                stashId: "test-stash-id",
                optCode: "123456"
            )
            XCTFail("Expected allHostsFailed error")
        } catch let error as QRTriggerDownloadClientError {
            if case .allHostsFailed = error {
                XCTAssertEqual(callCount, 2)
            } else {
                XCTFail("Expected allHostsFailed but got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClaimFailoverSecondHostSucceeds() async throws {
        var callCount = 0
        URLProtocolMock.requestHandler = { _ in
            callCount += 1
            if callCount == 1 {
                throw URLError(.cannotConnectToHost)
            }
            return URLProtocolMock.config(
                statusCode: 200,
                headers: ["Content-Type": "text/plain"],
                body: Data("Hello".utf8)
            )
        }

        urlSession = URLProtocolMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        let result = try await client.claim(
            hosts: ["192.168.1.10", "192.168.1.11"],
            port: 9527,
            stashId: "test-stash-id",
            optCode: "123456"
        )

        switch result {
        case .text(let text):
            XCTAssertEqual(text, "Hello")
        case .image:
            XCTFail("Expected text result")
        }

        XCTAssertEqual(callCount, 2)
    }
}

final class URLProtocolMock: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func config(statusCode: Int, headers: [String: String], body: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "http://test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, body)
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolMock.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = URLProtocolMock.requestHandler else {
            fatalError("URLProtocolMock.requestHandler not set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
