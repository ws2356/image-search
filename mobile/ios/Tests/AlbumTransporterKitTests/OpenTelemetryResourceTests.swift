import Foundation
import OpenTelemetryApi
import XCTest
@testable import AlbumTransporterKit

final class OpenTelemetryResourceTests: XCTestCase {
    func testResourceContainsGitRevisionAttribute() {
        let resource = OpenTelemetryTelemetryClient.makeResource(
            serviceName: "AuBackup.iOS",
            serviceVersion: "1.1.0"
        )
        let value = resource.attributes["app.git_revision"]
        XCTAssertNotNil(value)
        if case .string(let revision) = value {
            XCTAssertFalse(revision.isEmpty)
        } else {
            XCTFail("app.git_revision should be a string attribute")
        }
    }
}
