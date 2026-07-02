import XCTest
@testable import AlbumTransporterKit

final class AppUpdateServicesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppUpdateURLProtocol.reset()
    }

    override func tearDown() {
        AppUpdateURLProtocol.reset()
        super.tearDown()
    }

    func test_app_semantic_version_treats_missing_patch_as_equal() {
        XCTAssertEqual(AppSemanticVersion("1.0"), AppSemanticVersion("1.0.0"))
    }

    func test_app_semantic_version_compares_numeric_components() {
        XCTAssertLessThan(AppSemanticVersion("1.2.9")!, AppSemanticVersion("1.10.0")!)
    }

    func test_version_requirement_returns_prompt_when_current_version_is_too_old() {
        let requirement = AppUpdateVersionRequirement(minimumVersion: "2.3.4", required: true)

        let prompt = requirement.promptIfNeeded(
            currentVersion: "1.9.0",
            appStoreURL: URL(string: "https://apps.apple.com/app/id6764228721")!
        )

        XCTAssertEqual(prompt?.minimumVersion, "2.3.4")
        XCTAssertEqual(prompt?.required, true)
    }

    func test_fetch_version_requirement_decodes_remote_payload() async throws {
        AppUpdateURLProtocol.responseStatusCode = 200
        AppUpdateURLProtocol.responseData = #"{"version":{"min":"2.3.4","required":true}}"#.data(using: .utf8)
        let checker = makeChecker()

        let requirement = try await checker.fetchVersionRequirement()

        XCTAssertEqual(
            requirement,
            AppUpdateVersionRequirement(minimumVersion: "2.3.4", required: true)
        )
    }

    func test_fetch_version_requirement_rejects_non_success_status() async {
        AppUpdateURLProtocol.responseStatusCode = 503
        AppUpdateURLProtocol.responseData = #"{"version":{"min":"2.3.4","required":true}}"#.data(using: .utf8)
        let checker = makeChecker()

        await XCTAssertThrowsErrorAsync(try await checker.fetchVersionRequirement()) { error in
            XCTAssertEqual(error as? AppUpdateCheckError, .invalidStatusCode(503))
        }
    }

    func test_fetch_version_requirement_rejects_invalid_minimum_version() async {
        AppUpdateURLProtocol.responseStatusCode = 200
        AppUpdateURLProtocol.responseData = #"{"version":{"min":"beta","required":false}}"#.data(using: .utf8)
        let checker = makeChecker()

        await XCTAssertThrowsErrorAsync(try await checker.fetchVersionRequirement()) { error in
            XCTAssertEqual(error as? AppUpdateCheckError, .invalidPayload)
        }
    }

    private func makeChecker() -> URLSessionAppUpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppUpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return URLSessionAppUpdateChecker(
            session: session,
            endpoint: URL(string: "https://api.boldman.net/aubackup/features")!
        )
    }
}

private final class AppUpdateURLProtocol: URLProtocol {
    static var responseData: Data?
    static var responseStatusCode = 200

    static func reset() {
        responseData = nil
        responseStatusCode = 200
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let responseData = Self.responseData {
            client?.urlProtocol(self, didLoad: responseData)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw an error")
    } catch {
        errorHandler(error)
    }
}
