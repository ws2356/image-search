import XCTest
@testable import ISFromPC

@MainActor
final class MultiFileReceiveViewModelTests: XCTestCase {
    private final class StubDelegate: ISQRDeliverDelegate {
        func onDeliverComplete() {}
    }

    func test_inlineTextResult_isInitializedAsDownloaded() {
        let manifest = MultiFileManifest(
            fileCount: 1,
            files: [
                .init(index: 0, type: "text", filename: "notes.txt",
                      contentType: "text/plain", sizeBytes: 10,
                      content: "hello")
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "host",
            tlsPort: 8443,
            sessionId: "sid",
            correlationID: "cid",
            delegate: StubDelegate()
        )

        XCTAssertEqual(vm.fileStates.count, 1)
        XCTAssertEqual(vm.fileStates[0].status, .downloaded)
        if case .text(let value) = vm.fileStates[0].result {
            XCTAssertEqual(value, "hello")
        } else {
            XCTFail("Expected text result")
        }
    }

    func test_inlineHtmlResult_preservesHtmlResultType() {
        let manifest = MultiFileManifest(
            fileCount: 1,
            files: [
                .init(index: 0, type: "html", filename: "note.html",
                      contentType: "text/html", sizeBytes: 20,
                      content: "<p>hi</p>")
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "host",
            tlsPort: 8443,
            sessionId: "sid",
            correlationID: "cid",
            delegate: StubDelegate()
        )

        if case .html(let value) = vm.fileStates[0].result {
            XCTAssertEqual(value, "<p>hi</p>")
        } else {
            XCTFail("Expected html result")
        }
    }

    func test_singleTextResult_wrapsIntoOneItemState() {
        let vm = MultiFileReceiveViewModel(
            singleResult: .text("hello"),
            delegate: StubDelegate()
        )

        XCTAssertEqual(vm.fileStates.count, 1)
        XCTAssertEqual(vm.fileStates[0].entryType, "text")
        XCTAssertEqual(vm.fileStates[0].status, .downloaded)
    }

    func test_singleLinkResult_wrapsIntoOneItemState() {
        let vm = MultiFileReceiveViewModel(
            singleResult: .link("https://example.com"),
            delegate: StubDelegate()
        )

        XCTAssertEqual(vm.fileStates.count, 1)
        XCTAssertEqual(vm.fileStates[0].entryType, "link")
        XCTAssertEqual(vm.fileStates[0].status, .downloaded)
    }

    func test_shareAll_setsShareItemsForAllDownloadedStates() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("vm-test")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("doc.txt")
        try? Data("content".utf8).write(to: fileURL)

        let vm = MultiFileReceiveViewModel(
            singleResult: .file(fileURL: fileURL, contentType: "text/plain", filename: "doc.txt"),
            delegate: StubDelegate()
        )
        vm.shareAll()

        XCTAssertEqual(vm.shareItems.count, 1)
        XCTAssertTrue(vm.showShareSheet)

        try? FileManager.default.removeItem(at: tempDir)
    }
}
