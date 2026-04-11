import Foundation
import XCTest
@testable import AlbumTransporterKit

final class TransferServiceTests: XCTestCase {
    func test_photo_library_transfer_service_uploads_assets_and_completes_session() async throws {
        let trustedDesktopStore = InMemoryTransferTrustedDesktopStore(
            record: TrustedDesktopRecord(
                desktopDeviceID: "desktop-device-001",
                desktopName: "Studio Mac",
                endpointURL: URL(string: "http://192.168.50.17:38933/api/mobile/pairing/claim")!,
                mobileDeviceUUID: "ios-device-001",
                sharedKeyBase64: "shared-key-001",
                transport: .lan,
                lastSessionID: "pairing-demo-001",
                pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
            )
        )
        let assetSource = StaticTransferAssetSource(
            descriptors: [
                TransferAssetDescriptor(
                    assetID: "ph://asset-001",
                    assetVersion: "v1",
                    filename: "IMG_0001.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_610),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_610)
                ),
                TransferAssetDescriptor(
                    assetID: "ph://asset-002",
                    assetVersion: "v2",
                    filename: "VID_0001.MOV",
                    mediaType: "video",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_710),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_710)
                ),
            ]
        )
        let transferClient = RecordingMobileTransferClient()
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let startSnapshot = await service.startTransfer()
        let completedSnapshot = await service.completeTransfer(current: startSnapshot)
        let uploadedAssetIDs = await transferClient.uploadedAssetIDs()
        let startedAssetCount = await transferClient.startedAssetCount()
        let completedTransferredCount = await transferClient.completedTransferredCount()
        let completedFailedCount = await transferClient.completedFailedCount()

        XCTAssertEqual(startSnapshot.transferredCount, 2)
        XCTAssertEqual(startSnapshot.totalCount, 2)
        XCTAssertEqual(startSnapshot.failedCount, 0)
        XCTAssertEqual(uploadedAssetIDs, ["ph://asset-001", "ph://asset-002"])
        XCTAssertEqual(startedAssetCount, 2)
        XCTAssertEqual(completedTransferredCount, 2)
        XCTAssertEqual(completedFailedCount, 0)
        XCTAssertEqual(
            completedSnapshot.statusMessage,
            "Desktop confirmed that this transfer session is complete."
        )
    }

    func test_photo_library_transfer_service_reports_missing_desktop_record() async {
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: []),
            transferClient: RecordingMobileTransferClient(),
            trustedDesktopStore: InMemoryTransferTrustedDesktopStore(record: nil)
        )

        let snapshot = await service.startTransfer()

        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(
            snapshot.statusMessage,
            "No paired desktop record is available for transfer."
        )
    }

    func test_photo_library_transfer_service_points_failed_assets_to_device_logs() async {
        let trustedDesktopStore = InMemoryTransferTrustedDesktopStore(
            record: TrustedDesktopRecord(
                desktopDeviceID: "desktop-device-001",
                desktopName: "Studio Mac",
                endpointURL: URL(string: "http://192.168.50.17:38933/api/mobile/pairing/claim")!,
                mobileDeviceUUID: "ios-device-001",
                sharedKeyBase64: "shared-key-001",
                transport: .lan,
                lastSessionID: "pairing-demo-001",
                pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
            )
        )
        let assetSource = StaticTransferAssetSource(
            descriptors: [
                TransferAssetDescriptor(
                    assetID: "ph://asset-001",
                    assetVersion: "v1",
                    filename: "IMG_0001.HEIC",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_610),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_610)
                ),
                TransferAssetDescriptor(
                    assetID: "ph://asset-002",
                    assetVersion: "v2",
                    filename: "IMG_0002.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_710),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_710)
                ),
            ],
            failingAssetIDs: ["ph://asset-002"]
        )
        let transferClient = RecordingMobileTransferClient()
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer()

        XCTAssertEqual(snapshot.transferredCount, 1)
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.failedCount, 1)
        XCTAssertTrue(snapshot.guidanceMessage.contains("MobileTransfer device logs"))
    }
}

private actor InMemoryTransferTrustedDesktopStore: TrustedDesktopStore {
    private var record: TrustedDesktopRecord?

    init(record: TrustedDesktopRecord?) {
        self.record = record
    }

    func loadTrustedDesktop() async -> TrustedDesktopRecord? {
        record
    }

    func saveTrustedDesktop(_ record: TrustedDesktopRecord) async {
        self.record = record
    }
}

private actor RecordingMobileTransferClient: MobileTransferClient {
    private var startedCount: Int?
    private var uploadedIDs: [String] = []
    private var completedTransferred: Int?
    private var completedFailed: Int?

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        XCTAssertEqual(desktop.desktopName, "Studio Mac")
        startedCount = totalAssets
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        uploadedIDs.append(asset.descriptor.assetID)
        return TransferServerResponse(
            schema: TransferProtocol.schema,
            status: asset.descriptor.assetID == "ph://asset-002" ? .skipped : .stored,
            message: "ok",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: "2026-04/\(asset.descriptor.filename)"
        )
    }

    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse {
        completedTransferred = transferredCount
        completedFailed = failedCount
        return TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .completed,
            message: "done",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: nil
        )
    }

    func startedAssetCount() -> Int? {
        startedCount
    }

    func uploadedAssetIDs() -> [String] {
        uploadedIDs
    }

    func completedTransferredCount() -> Int? {
        completedTransferred
    }

    func completedFailedCount() -> Int? {
        completedFailed
    }
}

private actor StaticTransferAssetSource: TransferAssetSource {
    private let descriptors: [TransferAssetDescriptor]
    private let failingAssetIDs: Set<String>

    init(descriptors: [TransferAssetDescriptor], failingAssetIDs: Set<String> = []) {
        self.descriptors = descriptors
        self.failingAssetIDs = failingAssetIDs
    }

    func fetchAssets() async throws -> [TransferAssetDescriptor] {
        descriptors
    }

    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset {
        if failingAssetIDs.contains(descriptor.assetID) {
            throw TransferClientError.transport(message: "Synthetic export failure for tests.")
        }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension((descriptor.filename as NSString).pathExtension)
        try Data(descriptor.assetID.utf8).write(to: fileURL)
        return ExportedTransferAsset(
            descriptor: descriptor,
            fileURL: fileURL,
            mimeType: "application/octet-stream"
        )
    }
}
