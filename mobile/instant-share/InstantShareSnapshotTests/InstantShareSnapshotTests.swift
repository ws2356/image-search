import SwiftUI
import UIKit
import XCTest
@testable import ISFromPC
@testable import Common

@MainActor
final class InstantShareSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        SnapshotSupport.releaseWindow()
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Single Image Receive (via MultiFileReceiveView)

    func test_share_receive_single_image() throws {
        // Create a temporary image file to simulate a pre-downloaded image
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-images", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let imageURL = tempDir.appendingPathComponent("shared_photo.jpg")

        let jpegData = try loadDisneyImageJPEGData()
        try jpegData.write(to: imageURL)

        let result = QRClaimResult.image(fileURL: imageURL, contentType: "image/jpeg", filename: "shared_photo.jpg")
        let delegate = SnapshotISQRDeliverDelegate()
        let vm = MultiFileReceiveViewModel(singleResult: result, delegate: delegate)
        let view = MultiFileReceiveView(viewModel: vm)
        let viewController = makeHostedPage(title: "Received Files") { view }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-single-image", viewController: viewController)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Single File Receive (via MultiFileReceiveView)

    func test_share_receive_single_file() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-files", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("report.pdf")
        try Data("Sample PDF content".utf8).write(to: fileURL)

        let result = QRClaimResult.file(fileURL: fileURL, contentType: "application/pdf", filename: "report.pdf")
        let delegate = SnapshotISQRDeliverDelegate()
        let vm = MultiFileReceiveViewModel(singleResult: result, delegate: delegate)
        let view = MultiFileReceiveView(viewModel: vm)
        let viewController = makeHostedPage(title: "Received Files") { view }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-single-file", viewController: viewController)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Error State

    func test_share_receive_error() throws {
        let errorVM = ISQRErrorViewModel(
            title: "Transfer Failed",
            message: "Could not connect to your Mac. Make sure both devices are on the same Wi-Fi network.",
            delegate: SnapshotISQRErrorDelegate()
        )
        let viewController = makeHostedPage(title: "Error") {
            ErrorStateView(viewModelFactory: { errorVM })
        }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-error", viewController: viewController)
    }

    // MARK: - Claiming (Loading Spinner)

    func test_share_receive_claiming() throws {
        let payload = QRClaimPayload(
            ips: ["192.168.1.100"],
            port: 8080,
            tlsPort: 8443,
            sessionId: "test-session-123",
            optCode: "ABCD",
            deviceId: "test-device"
        )
        let delegate = SnapshotQRClaimDelegate()
        let view = QRClaimView(qrClaimPayload: payload, delegate: delegate)
        let viewController = makeHostedPage(title: "Connecting") { view }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-claiming", viewController: viewController)
    }

    // MARK: - Text Card

    func test_share_receive_text_card() throws {
        let manifest = MultiFileManifest(
            fileCount: 1,
            files: [
                .init(
                    index: 0,
                    type: "text",
                    filename: "notes.txt",
                    contentType: "text/plain",
                    sizeBytes: 1234,
                    content: "Hello from Mac!\n\nThis is a shared text message with multiple lines."
                )
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "192.168.1.100",
            tlsPort: 8443,
            sessionId: "test-session",
            correlationID: "test-correlation",
            delegate: SnapshotISQRDeliverDelegate()
        )
        let viewController = makeHostedPage(title: "Received Files") {
            MultiFileReceiveView(viewModel: vm)
        }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-text-card", viewController: viewController)
    }

    // MARK: - HTML Card

    func test_share_receive_html_card() throws {
        let manifest = MultiFileManifest(
            fileCount: 1,
            files: [
                .init(
                    index: 0,
                    type: "html",
                    filename: "note.html",
                    contentType: "text/html",
                    sizeBytes: 2048,
                    content: "<html><body><h1>Hello</h1><p>Rich text preview.</p></body></html>"
                )
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "192.168.1.100",
            tlsPort: 8443,
            sessionId: "test-session",
            correlationID: "test-correlation",
            delegate: SnapshotISQRDeliverDelegate()
        )
        let viewController = makeHostedPage(title: "Received Files") {
            MultiFileReceiveView(viewModel: vm)
        }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-html-card", viewController: viewController)
    }

    // MARK: - Web Link Card

    func test_share_receive_link_card() throws {
        let result = QRClaimResult.link("https://example.com/shared-document")
        let vm = MultiFileReceiveViewModel(singleResult: result, delegate: SnapshotISQRDeliverDelegate())
        let viewController = makeHostedPage(title: "Received Files") {
            MultiFileReceiveView(viewModel: vm)
        }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-link-card", viewController: viewController)
    }

    // MARK: - Mixed File List

    func test_share_receive_mixed_list() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-test-mixed", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let imageURL = tempDir.appendingPathComponent("vacation_photo.jpg")
        let jpegData = try loadDisneyImageJPEGData()
        try jpegData.write(to: imageURL)

        let manifest = MultiFileManifest(
            fileCount: 3,
            files: [
                .init(
                    index: 0,
                    type: "text",
                    filename: "gllue_links.txt",
                    contentType: "text/plain",
                    sizeBytes: 1200,
                    content: "x.gllue.com\nGllue - Remember me Sign In\nhire58.com.cn"
                ),
                .init(
                    index: 1,
                    type: "file",
                    filename: "vacation_photo.jpg",
                    contentType: "image/jpeg",
                    sizeBytes: 2_400_000,
                    content: nil
                ),
                .init(
                    index: 2,
                    type: "file",
                    filename: "design_assets.zip",
                    contentType: "application/zip",
                    sizeBytes: 24_700_000,
                    content: nil
                )
            ]
        )
        let vm = MultiFileReceiveViewModel(
            manifest: manifest,
            host: "192.168.1.100",
            tlsPort: 8443,
            sessionId: "test-session",
            correlationID: "test-correlation",
            delegate: SnapshotISQRDeliverDelegate()
        )
        // Pre-populate the image result so the card renders the thumbnail.
        if let index = vm.fileStates.firstIndex(where: { $0.filename == "vacation_photo.jpg" }) {
            vm.fileStates[index].result = .image(fileURL: imageURL, contentType: "image/jpeg", filename: "vacation_photo.jpg")
            vm.fileStates[index].status = .downloaded
        }
        // Mark the zip file as downloaded with a temp file so the list is stable.
        let zipURL = tempDir.appendingPathComponent("design_assets.zip")
        try Data("zip contents".utf8).write(to: zipURL)
        if let index = vm.fileStates.firstIndex(where: { $0.filename == "design_assets.zip" }) {
            vm.fileStates[index].result = .file(fileURL: zipURL, contentType: "application/zip", filename: "design_assets.zip")
            vm.fileStates[index].status = .downloaded
        }
        let viewController = makeHostedPage(title: "Received Files") {
            MultiFileReceiveView(viewModel: vm)
        }
        try SnapshotSupport.assertSnapshot(pageName: "share-receive-mixed-list", viewController: viewController)

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func loadDisneyImageJPEGData() throws -> Data {
        let testFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("disney.HEIC")
        guard let image = UIImage(contentsOfFile: testFileURL.path) else {
            throw NSError(domain: "SnapshotTests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not load disney.HEIC at \(testFileURL.path)"])
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "SnapshotTests", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not convert disney.HEIC to JPEG"])
        }
        return jpegData
    }

    private func makeHostedPage<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> UIViewController {
        let controller = UIHostingController(
            rootView: SnapshotPageHost(title: title, content: content)
        )
        controller.view.backgroundColor = .clear
        return controller
    }
}

// MARK: - Snapshot Delegate Stubs

@MainActor
private final class SnapshotISQRDeliverDelegate: ISQRDeliverDelegate {
    func onDeliverComplete() {}
}

@MainActor
private final class SnapshotISQRErrorDelegate: ISQRErrorDelegate {
    func onErrorHandlingResult(_ result: ErrorHandlingResult) {}
}

@MainActor
private final class SnapshotQRClaimDelegate: QRClaimDelegate {
    func onClaimCompletion(_ result: Result<QRClaimResult, any Error>) {}
}

// MARK: - QRClaimPayload Convenience Init

private extension QRClaimPayload {
    init(
        ips: [String],
        port: Int,
        tlsPort: Int,
        sessionId: String,
        optCode: String,
        deviceId: String
    ) {
        let urlString = "https://dl.boldman.net/share?ips=\(ips.joined(separator: ","))&p=\(port)&sp=\(tlsPort)&sid=\(sessionId)&opt=\(optCode)&did=\(deviceId)"
        self.init(universalLinkURL: URL(string: urlString)!)!
    }
}
