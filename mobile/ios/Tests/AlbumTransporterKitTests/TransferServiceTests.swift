import CryptoKit
import Foundation
import XCTest
@testable import AlbumTransporterKit

final class TransferServiceTests: XCTestCase {
    func test_transfer_asset_chunk_streamer_splits_chunks_at_configured_size() async throws {
        let totalSize = TransferAssetStreamProtocol.chunkSizeBytes + 257
        let payload = Data(
            (0 ..< totalSize).map { index in
                UInt8(index % 251)
            }
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension("bin")
        try payload.write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let recorder = ChunkSizeRecorder()
        try await TransferAssetChunkStreamer.streamFile(
            fileURL: fileURL,
            expectedSizeBytes: totalSize
        ) { chunk in
            await recorder.append(chunk.count)
        }

        let chunkSizes = await recorder.snapshot()
        XCTAssertEqual(chunkSizes, [TransferAssetStreamProtocol.chunkSizeBytes, 257])
    }

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

        let startSnapshot = await service.startTransfer(progress: { _ in })
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

        let snapshot = await service.startTransfer(progress: { _ in })

        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(
            snapshot.statusMessage,
            "No paired desktop record is available for transfer."
        )
    }

    func test_photo_library_transfer_service_uses_resolved_transport_for_progress() async {
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
            ]
        )
        let transferClient = RecordingMobileTransferClient(resolvedTransport: .usb)
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer(progress: { _ in })

        XCTAssertEqual(snapshot.transport, .usb)
    }

    func test_photo_library_transfer_service_progress_snapshot_refreshes_transport_without_new_events() async {
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
        let transferClient = RecordingMobileTransferClient(resolvedTransport: .lan)
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: []),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        _ = await service.startTransfer(progress: { _ in })
        await transferClient.setResolvedTransport(.usb)
        let refreshedSnapshot = await service.progressSnapshot()

        XCTAssertEqual(refreshedSnapshot?.transport, .usb)
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

        let snapshot = await service.startTransfer(progress: { _ in })

        XCTAssertEqual(snapshot.transferredCount, 1)
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.failedCount, 1)
        XCTAssertTrue(snapshot.guidanceMessage.contains("MobileTransfer device logs"))
    }

    func test_photo_library_transfer_service_emits_progress_updates_during_transfer() async {
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
                    filename: "IMG_0002.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_710),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_710)
                ),
            ]
        )
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: RecordingMobileTransferClient(),
            trustedDesktopStore: trustedDesktopStore
        )
        let recorder = ProgressSnapshotRecorder()

        let finalSnapshot = await service.startTransfer { snapshot in
            recorder.record(snapshot)
        }
        let recordedSnapshots = recorder.snapshots()

        XCTAssertEqual(recordedSnapshots.map(\.totalCount), [2, 2, 2])
        XCTAssertEqual(recordedSnapshots.map(\.transferredCount), [0, 1, 2])
        XCTAssertTrue(recordedSnapshots.allSatisfy { $0.transferSpeedText != nil })
        XCTAssertEqual(finalSnapshot.transferredCount, 2)
        XCTAssertEqual(finalSnapshot.totalCount, 2)
    }

    func test_photo_library_transfer_service_limits_concurrent_uploads_to_ten_assets() async {
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
        let descriptors = (1 ... 24).map { index in
            TransferAssetDescriptor(
                assetID: String(format: "ph://asset-%03d", index),
                assetVersion: "v\(index)",
                filename: String(format: "IMG_%04d.JPG", index),
                mediaType: "image",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_776_123_610 + index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_776_123_610 + index))
            )
        }
        let transferClient = RecordingMobileTransferClient(uploadDelayNanoseconds: 50_000_000)
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: descriptors),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 10
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let maxConcurrentUploads = await transferClient.maxConcurrentUploadsObserved()

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertGreaterThan(maxConcurrentUploads, 1)
        XCTAssertLessThanOrEqual(maxConcurrentUploads, 10)
    }

    func test_photo_library_transfer_service_memory_warning_keeps_upload_concurrency_limit() async {
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
        let descriptors = (1 ... 24).map { index in
            TransferAssetDescriptor(
                assetID: String(format: "ph://asset-%03d", index),
                assetVersion: "v\(index)",
                filename: String(format: "IMG_%04d.JPG", index),
                mediaType: "image",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_776_323_610 + index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_776_323_610 + index))
            )
        }
        let transferClient = RecordingMobileTransferClient(uploadDelayNanoseconds: 50_000_000)
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: descriptors),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 10
        )
        await service.handleMemoryWarning()
        await service.handleMemoryWarning()

        let snapshot = await service.startTransfer(progress: { _ in })
        let maxConcurrentUploads = await transferClient.maxConcurrentUploadsObserved()

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertGreaterThan(maxConcurrentUploads, 1)
        XCTAssertLessThanOrEqual(maxConcurrentUploads, 10)
    }

    func test_photo_library_transfer_service_allows_usb_upload_concurrency_when_supported() async {
        let trustedDesktopStore = InMemoryTransferTrustedDesktopStore(
            record: TrustedDesktopRecord(
                desktopDeviceID: "desktop-device-001",
                desktopName: "Studio Mac",
                endpointURL: URL(string: "http://192.168.50.17:38933/api/mobile/pairing/claim")!,
                mobileDeviceUUID: "ios-device-001",
                sharedKeyBase64: "shared-key-001",
                transport: .usb,
                lastSessionID: "pairing-demo-001",
                pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
            )
        )
        let descriptors = (1 ... 12).map { index in
            TransferAssetDescriptor(
                assetID: String(format: "ph://asset-%03d", index),
                assetVersion: "v\(index)",
                filename: String(format: "IMG_%04d.JPG", index),
                mediaType: "image",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_776_223_610 + index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_776_223_610 + index))
            )
        }
        let transferClient = RecordingMobileTransferClient(
            resolvedTransport: .usb,
            uploadDelayNanoseconds: 40_000_000
        )
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: descriptors),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 10
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let maxConcurrentUploads = await transferClient.maxConcurrentUploadsObserved()

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertGreaterThan(maxConcurrentUploads, 1)
        XCTAssertLessThanOrEqual(maxConcurrentUploads, 10)
    }

    func test_photo_library_transfer_service_dual_channel_scheduler_uses_usb_and_lan_lanes() async {
        let trustedDesktopStore = InMemoryTransferTrustedDesktopStore(
            record: TrustedDesktopRecord(
                desktopDeviceID: "desktop-device-001",
                desktopName: "Studio Mac",
                endpointURL: URL(string: "http://192.168.50.17:38933/api/mobile/pairing/claim")!,
                mobileDeviceUUID: "ios-device-001",
                sharedKeyBase64: "shared-key-001",
                transport: .usb,
                lastSessionID: "pairing-demo-001",
                pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
            )
        )
        let descriptors = (1 ... 20).map { index in
            TransferAssetDescriptor(
                assetID: String(format: "ph://asset-%03d", index),
                assetVersion: "v\(index)",
                filename: String(format: "IMG_%04d.JPG", index),
                mediaType: "image",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_776_123_610 + index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_776_123_610 + index))
            )
        }
        let transferClient = RecordingMobileTransferClient(
            resolvedTransport: .usb,
            uploadDelayNanoseconds: 40_000_000
        )
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: descriptors),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 10
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let observedTransports = await transferClient.observedPreferredUploadTransports()
        let usbUploads = observedTransports.filter { $0 == .usb }.count
        let lanUploads = observedTransports.filter { $0 == .lan }.count

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(observedTransports.count, descriptors.count)
        XCTAssertGreaterThan(usbUploads, 0)
        XCTAssertGreaterThan(lanUploads, 0)
    }

    func test_photo_library_transfer_service_skips_known_assets_before_upload() async {
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
                    filename: "IMG_0002.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_710),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_710)
                ),
            ]
        )
        let transferClient = RecordingMobileTransferClient(existingAssetIDs: ["ph://asset-001"])
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let uploadedAssetIDs = await transferClient.uploadedAssetIDs()
        let lookupBatchSizes = await transferClient.lookupBatchSizes()

        XCTAssertEqual(snapshot.transferredCount, 2)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(uploadedAssetIDs, ["ph://asset-002"])
        XCTAssertEqual(lookupBatchSizes, [1, 1])
    }

    func test_photo_library_transfer_service_checks_desktop_existence_per_asset() async {
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
                    filename: "IMG_0002.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_710),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_710)
                ),
                TransferAssetDescriptor(
                    assetID: "ph://asset-003",
                    assetVersion: "v3",
                    filename: "IMG_0003.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_810),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_810)
                ),
            ]
        )
        let transferClient = RecordingMobileTransferClient()
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let uploadedAssetIDs = await transferClient.uploadedAssetIDs()
        let lookupBatchSizes = await transferClient.lookupBatchSizes()

        XCTAssertEqual(snapshot.transferredCount, 3)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(uploadedAssetIDs, ["ph://asset-001", "ph://asset-002", "ph://asset-003"])
        XCTAssertEqual(lookupBatchSizes, [1, 1, 1])
    }

    func test_photo_library_transfer_service_per_asset_lookup_ignores_batch_threshold_settings() async {
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
                    filename: "IMG_0002.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_710),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_710)
                ),
                TransferAssetDescriptor(
                    assetID: "ph://asset-003",
                    assetVersion: "v3",
                    filename: "IMG_0003.JPG",
                    mediaType: "image",
                    createdAt: Date(timeIntervalSince1970: 1_776_123_810),
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_810)
                ),
            ],
            exportedSizeByAssetID: [
                "ph://asset-001": 12,
                "ph://asset-002": 12,
                "ph://asset-003": 12,
            ]
        )
        let transferClient = RecordingMobileTransferClient()
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let uploadedAssetIDs = await transferClient.uploadedAssetIDs()
        let lookupBatchSizes = await transferClient.lookupBatchSizes()

        XCTAssertEqual(snapshot.transferredCount, 3)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(uploadedAssetIDs, ["ph://asset-001", "ph://asset-002", "ph://asset-003"])
        XCTAssertEqual(lookupBatchSizes, [1, 1, 1])
    }

    func test_photo_library_transfer_service_reports_stop_to_desktop_as_interrupted() async {
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
        let transferClient = RecordingMobileTransferClient()
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: []),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )
        let currentSnapshot = TransferSnapshot(
            transferredCount: 3,
            totalCount: 10,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Stopping backup…",
            guidanceMessage: "",
            isIncompleteLibrary: false
        )

        let reason = await service.stopTransfer(current: currentSnapshot)
        let completedTransferredCount = await transferClient.completedTransferredCount()
        let completedFailedCount = await transferClient.completedFailedCount()
        let completedInterruptionReason = await transferClient.completedInterruptionReason()

        XCTAssertEqual(reason, .stoppedByUser)
        XCTAssertEqual(completedTransferredCount, 3)
        XCTAssertEqual(completedFailedCount, 0)
        XCTAssertEqual(completedInterruptionReason, "stopped_by_user")
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

private actor ChunkSizeRecorder {
    private var sizes: [Int] = []

    func append(_ size: Int) {
        sizes.append(size)
    }

    func snapshot() -> [Int] {
        sizes
    }
}

private actor RecordingMobileTransferClient: PreferredTransportMobileTransferClient, TransferTransportResolving {
    private var startedCount: Int?
    private let existingAssetIDs: Set<String>
    private let uploadDelayNanoseconds: UInt64
    private var resolvedTransport: TransferTransport?
    private var lookupAssetIDsByBatch: [[String]] = []
    private var uploadedIDs: [String] = []
    private var activeUploadCount = 0
    private var maxConcurrentUploadCount = 0
    private var completedTransferred: Int?
    private var completedFailed: Int?
    private var completedInterruptionReasonValue: String?
    private var preferredUploadTransports: [TransferTransport] = []

    init(
        existingAssetIDs: Set<String> = [],
        resolvedTransport: TransferTransport? = nil,
        uploadDelayNanoseconds: UInt64 = 0
    ) {
        self.existingAssetIDs = existingAssetIDs
        self.resolvedTransport = resolvedTransport
        self.uploadDelayNanoseconds = uploadDelayNanoseconds
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        XCTAssertEqual(desktop.desktopName, "Studio Mac")
        startedCount = totalAssets
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        lookupAssetIDsByBatch.append(candidates.map(\.assetID))
        return Dictionary(
            uniqueKeysWithValues: candidates.compactMap { candidate in
                guard existingAssetIDs.contains(candidate.assetID) else {
                    return nil
                }
                return (
                    candidate.assetID,
                    TransferAssetExistenceMatch(
                        assetID: candidate.assetID,
                        localRelativePath: "2026-04/\(candidate.assetID.replacingOccurrences(of: "://", with: "-")).bin"
                    )
                )
            }
        )
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> [String: TransferAssetExistenceMatch] {
        try await lookupExistingAssets(candidates, desktop: desktop)
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        try await uploadAsset(
            asset,
            desktop: desktop,
            preferredTransport: nil
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> TransferServerResponse {
        if let preferredTransport {
            preferredUploadTransports.append(preferredTransport)
        }
        activeUploadCount += 1
        maxConcurrentUploadCount = max(maxConcurrentUploadCount, activeUploadCount)
        defer {
            activeUploadCount -= 1
        }
        if uploadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: uploadDelayNanoseconds)
        }
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

    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse {
        completedTransferred = transferredCount
        completedFailed = failedCount
        completedInterruptionReasonValue = interruptionReason
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

    func resolveDesktopTransport(for desktop: TrustedDesktopRecord) async -> TransferTransport {
        resolvedTransport ?? desktop.transport
    }

    func setResolvedTransport(_ transport: TransferTransport?) {
        resolvedTransport = transport
    }

    func startedAssetCount() -> Int? {
        startedCount
    }

    func lookupBatchSizes() -> [Int] {
        lookupAssetIDsByBatch.map(\.count)
    }

    func uploadedAssetIDs() -> [String] {
        uploadedIDs.sorted()
    }

    func completedTransferredCount() -> Int? {
        completedTransferred
    }

    func completedFailedCount() -> Int? {
        completedFailed
    }

    func completedInterruptionReason() -> String? {
        completedInterruptionReasonValue
    }

    func maxConcurrentUploadsObserved() -> Int {
        maxConcurrentUploadCount
    }

    func observedPreferredUploadTransports() -> [TransferTransport] {
        preferredUploadTransports
    }
}

private actor StaticTransferAssetSource: TransferAssetSource {
    private let descriptors: [TransferAssetDescriptor]
    private let failingAssetIDs: Set<String>
    private let exportedSizeByAssetID: [String: Int]

    init(
        descriptors: [TransferAssetDescriptor],
        failingAssetIDs: Set<String> = [],
        exportedSizeByAssetID: [String: Int] = [:]
    ) {
        self.descriptors = descriptors
        self.failingAssetIDs = failingAssetIDs
        self.exportedSizeByAssetID = exportedSizeByAssetID
    }

    func fetchAssets() async throws -> [TransferAssetDescriptor] {
        descriptors
    }

    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset {
        if failingAssetIDs.contains(descriptor.assetID) {
            throw TransferClientError.transport(message: "Synthetic export failure for tests.")
        }
        let payloadSize = max(1, exportedSizeByAssetID[descriptor.assetID] ?? descriptor.assetID.utf8.count)
        let payload = Data(repeating: 0x5a, count: payloadSize)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension((descriptor.filename as NSString).pathExtension)
        try payload.write(to: fileURL)
        return ExportedTransferAsset(
            descriptor: descriptor,
            fileURL: fileURL,
            mimeType: "application/octet-stream",
            fileSize: payload.count,
            contentSHA1: sha1Hex(for: payload)
        )
    }
}

private final class ProgressSnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedSnapshots: [TransferSnapshot] = []

    func record(_ snapshot: TransferSnapshot) {
        lock.lock()
        recordedSnapshots.append(snapshot)
        lock.unlock()
    }

    func snapshots() -> [TransferSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSnapshots
    }
}

private func sha1Hex(for data: Data) -> String {
    Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
