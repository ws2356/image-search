import Foundation
import XCTest
@testable import AlbumTransporterKit

final class BundleBuildMetadataTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleBuildMetadataTests", isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testGitRevisionReads40CharHash() throws {
        let jsonURL = tempDir.appendingPathComponent("BuildMetadata.json")
        let hash = String(repeating: "a", count: 40)
        let json = "{\"GitRevision\":\"\(hash)\"}"
        try json.write(to: jsonURL, atomically: true, encoding: .utf8)

        let bundle = Bundle(url: tempDir)!
        XCTAssertEqual(bundle.gitRevision(), hash)
        XCTAssertEqual(bundle.buildMetadata()?["GitRevision"], hash)
    }

    func testMissingPlistReturnsNil() {
        let bundle = Bundle(url: tempDir)!
        XCTAssertNil(bundle.gitRevision())
        XCTAssertNil(bundle.buildMetadata())
    }
}
