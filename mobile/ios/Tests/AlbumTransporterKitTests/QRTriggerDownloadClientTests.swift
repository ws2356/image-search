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
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain; charset=utf-8"]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try expectedText.data(using: .utf8)!.write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        case .file:
            XCTFail("Expected text result but got file")
        }
    }

    func testClaimImageSuccess() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic bytes
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "image/png",
                    "X-Original-Filename": "photo.png",
                ]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try imageData.write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        case .image(let fileURL, let contentType, let filename):
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertEqual(contentType, "image/png")
            XCTAssertEqual(filename, "photo.png")
        case .file:
            XCTFail("Expected image result but got file")
        }
    }

    func testClaimFileSuccess() async throws {
        let fileData = Data([0x00, 0x01, 0x02, 0x03])
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/octet-stream",
                    "X-Original-Filename": "document.bin",
                ]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileData.write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
        client = QRTriggerDownloadClient(urlSession: urlSession)

        let result = try await client.claim(
            hosts: ["192.168.1.10"],
            port: 9527,
            stashId: "test-stash-id",
            optCode: "123456"
        )

        switch result {
        case .text:
            XCTFail("Expected file result but got text")
        case .image:
            XCTFail("Expected file result but got image")
        case .file(let fileURL, let contentType, let filename):
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
            XCTAssertEqual(contentType, "application/octet-stream")
            XCTAssertEqual(filename, "document.bin")
        }
    }

    func testClaimInvalidOptCode() async {
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("{\"error\":\"Invalid opt-code\"}".utf8).write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 410,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("{\"error\":\"Stash has expired\"}".utf8).write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("{\"error\":\"Stash not found\"}".utf8).write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        DownloadMock.responseHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("{\"error\":\"Internal error\"}".utf8).write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        DownloadMock.responseHandler = { _ in
            callCount += 1
            throw URLError(.cannotConnectToHost)
        }

        urlSession = DownloadMock.session()
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
        DownloadMock.responseHandler = { _ in
            callCount += 1
            if callCount == 1 {
                throw URLError(.cannotConnectToHost)
            }
            let response = HTTPURLResponse(
                url: URL(string: "http://test")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("Hello".utf8).write(to: tempURL)
            return (response, tempURL)
        }

        urlSession = DownloadMock.session()
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
        case .file:
            XCTFail("Expected text result but got file")
        }

        XCTAssertEqual(callCount, 2)
    }
}

final class DownloadMock: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    nonisolated(unsafe) static var responseHandler: ((URLRequest) throws -> (HTTPURLResponse, URL))?
    private var completionData: Data?
    private var completionError: Error?

    static func session() -> URLSession {
        let delegate = DownloadMock()
        return URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let handler = DownloadMock.responseHandler else {
            fatalError("DownloadMock.responseHandler not set")
        }
        do {
            let (response, tempURL) = try handler(downloadTask.originalRequest!)
            let data = try Data(contentsOf: tempURL)
            try data.write(to: location)
        } catch {
            completionError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {}

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completionError = error
    }
}
