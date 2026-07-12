import XCTest
@testable import ISFromPC

final class TextPreviewContentResolverTests: XCTestCase {
    func testInlineTextReturnsContent() {
        let result = TextPreviewContentResolver.resolve(
            inlineContent: "Hello, world!",
            contentType: "text/plain",
            result: nil
        )
        XCTAssertEqual(result, "Hello, world!")
    }

    func testInlineTextTruncatedTo500Characters() {
        let longText = String(repeating: "a", count: 600)
        let result = TextPreviewContentResolver.resolve(
            inlineContent: longText,
            contentType: "text/plain",
            result: nil
        )
        XCTAssertEqual(result?.count, 500)
        XCTAssertTrue(result?.hasPrefix("aaa") == true)
    }

    func testTextFileReturnsContents() throws {
        let text = "File contents here"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "text/plain",
            result: .file(fileURL: url, contentType: "text/plain", filename: "test.txt")
        )
        XCTAssertEqual(result, text)
    }

    func testNonTextContentTypeReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).bin")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "application/octet-stream",
            result: .file(fileURL: url, contentType: "application/octet-stream", filename: "test.bin")
        )
        XCTAssertNil(result)
    }

    func testLargeFileReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        let largeText = String(repeating: "x", count: 1_048_577)
        try largeText.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "text/plain",
            result: .file(fileURL: url, contentType: "text/plain", filename: "large.txt")
        )
        XCTAssertNil(result)
    }

    func testEmptyInlineContentFallsBackToFile() throws {
        let text = "From file"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = TextPreviewContentResolver.resolve(
            inlineContent: nil,
            contentType: "text/plain",
            result: .file(fileURL: url, contentType: "text/plain", filename: "test.txt")
        )
        XCTAssertEqual(result, text)
    }
}
