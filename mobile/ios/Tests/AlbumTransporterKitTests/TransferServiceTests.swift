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
        let completedSnapshot = await service.completeTransfer()
        let uploadedAssetIDs = await transferClient.uploadedAssetIDs()
        let startedAssetCount = await transferClient.startedAssetCount()
        let completedTransferredCount = await transferClient.completedTransferredCount()
        let completedFailedCount = await transferClient.completedFailedCount()
        let releasedResourceCount = await assetSource.releaseTransferRunResourcesCount()

        XCTAssertEqual(startSnapshot.transferredCount, 2)
        XCTAssertEqual(startSnapshot.totalCount, 2)
        XCTAssertEqual(startSnapshot.failedCount, 0)
        XCTAssertEqual(uploadedAssetIDs, ["ph://asset-001", "ph://asset-002"])
        XCTAssertEqual(startedAssetCount, 2)
        XCTAssertEqual(completedTransferredCount, 2)
        XCTAssertEqual(completedFailedCount, 0)
        XCTAssertEqual(releasedResourceCount, 1)
        XCTAssertEqual(
            completedSnapshot.statusMessage,
            "Desktop confirmed that this transfer session is complete."
        )
    }

    func test_photo_library_transfer_service_reports_eta_for_inflight_snapshots() async {
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
        let descriptors = (1 ... 5).map { index in
            TransferAssetDescriptor(
                assetID: "ph://asset-\(index)",
                assetVersion: "v\(index)",
                filename: "IMG_\(index).JPG",
                mediaType: "image",
                createdAt: Date(timeIntervalSince1970: 1_776_123_610 + TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: 1_776_123_610 + TimeInterval(index))
            )
        }
        let assetSource = StaticTransferAssetSource(descriptors: descriptors)
        let transferClient = RecordingMobileTransferClient(uploadDelayNanoseconds: 300_000_000)
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 1
        )
        let progressRecorder = ProgressSnapshotRecorder()

        _ = await service.startTransfer { snapshot in
            progressRecorder.record(snapshot)
        }

        let snapshots = progressRecorder.snapshots().filter { snapshot in
            snapshot.totalCount > 0 && snapshot.transferredCount + snapshot.failedCount < snapshot.totalCount
        }
        XCTAssertTrue(
            snapshots.contains(where: { snapshot in
                guard let etaMinutes = snapshot.etaMinutes else {
                    return false
                }
                return etaMinutes > 0
            })
        )
    }

    func test_photo_library_transfer_service_records_asset_export_and_upload_spans() async {
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
        let descriptor = TransferAssetDescriptor(
            assetID: "ph://asset-telemetry-001",
            assetVersion: "v3",
            filename: "IMG_9001.HEIC",
            mediaType: "image",
            createdAt: Date(timeIntervalSince1970: 1_776_123_810),
            updatedAt: Date(timeIntervalSince1970: 1_776_123_810)
        )
        let assetSource = StaticTransferAssetSource(
            descriptors: [descriptor],
            exportedSizeByAssetID: [descriptor.assetID: 4096]
        )
        let telemetryClient = RecordingSpanTelemetryClient()
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: RecordingMobileTransferClient(),
            trustedDesktopStore: trustedDesktopStore,
            telemetryClient: telemetryClient
        )

        _ = await service.startTransfer(progress: { _ in })
        let spans = await telemetryClient.recordedSpans()

        XCTAssertEqual(spans.map(\.name), ["mobile.backup.asset.export", "mobile.backup.asset.upload"])
        XCTAssertEqual(spans[0].attributes["correlation.session_id"], .string("pairing-demo-001"))
        XCTAssertEqual(spans[0].attributes["transfer.asset_id"], .string(descriptor.assetID))
        XCTAssertEqual(spans[0].attributes["transfer.pipeline_stage"], .string("export"))
        XCTAssertEqual(spans[1].attributes["transfer.pipeline_stage"], .string("upload"))
        XCTAssertEqual(spans[1].attributes["transfer.asset_file_size_bytes"], .int(4096))
    }

    func test_photo_library_transfer_service_reports_missing_desktop_record() async {
        let assetSource = StaticTransferAssetSource(descriptors: [])
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: RecordingMobileTransferClient(),
            trustedDesktopStore: InMemoryTransferTrustedDesktopStore(record: nil)
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let releasedResourceCount = await assetSource.releaseTransferRunResourcesCount()

        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(releasedResourceCount, 1)
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
        let transferClient = RecordingMobileTransferClient(
            resolvedTransport: .lan,
            liveTransports: [.lan]
        )
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: []),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        _ = await service.startTransfer(progress: { _ in })
        await transferClient.setResolvedTransport(.usb)
        await transferClient.setLiveTransports([.usb, .lan])
        let refreshedSnapshot = await service.progressSnapshot()

        XCTAssertEqual(refreshedSnapshot?.transport, .usb)
        XCTAssertEqual(refreshedSnapshot?.liveTransports, [.usb, .lan])
    }

    func test_photo_library_transfer_service_reports_usb_alive_through_adaptive_transfer_client() async {
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
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: RecordingMobileTransferClient(),
            usbClient: RecordingMobileTransferClient(usbConnected: true)
        )
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: []),
            transferClient: adaptiveClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let usbAlive = await service.isUSBTransportAlive()

        XCTAssertTrue(usbAlive)
    }

    func test_photo_library_transfer_service_exposes_both_live_transports_when_usb_and_lan_are_alive() async {
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
        let transferClient = RecordingMobileTransferClient(
            resolvedTransport: .usb,
            liveTransports: [.usb, .lan]
        )
        let service = PhotoLibraryTransferService(
            assetSource: StaticTransferAssetSource(descriptors: []),
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer(progress: { _ in })

        XCTAssertEqual(snapshot.transport, .usb)
        XCTAssertEqual(snapshot.liveTransports, [.usb, .lan])
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

    func test_photo_library_transfer_service_aborts_immediately_on_disk_full_terminal_failure() async {
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
        let transferClient = RecordingMobileTransferClient(
            uploadErrorByAssetID: [
                "ph://asset-001": .terminalFailure(
                    code: .diskFull,
                    message: "Desktop storage is full. Free up disk space on this PC and retry mobile backup."
                ),
            ]
        )
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 1
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let uploadedIDs = await transferClient.uploadedAssetIDs()

        XCTAssertEqual(snapshot.transferredCount, 0)
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.failedCount, 1)
        XCTAssertTrue(snapshot.statusMessage.contains("storage is full"))
        XCTAssertTrue(snapshot.guidanceMessage.contains("Free up disk space"))
        XCTAssertEqual(uploadedIDs, [])
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

    func test_photo_library_transfer_service_updates_speed_on_chunk_completion() async {
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
        let transferClient = RecordingMobileTransferClient(
            simulatedChunkTransferSizes: [5 * 1_024 * 1_024, 5 * 1_024 * 1_024]
        )
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )
        let recorder = ProgressSnapshotRecorder()

        let finalSnapshot = await service.startTransfer { snapshot in
            recorder.record(snapshot)
        }
        let recordedSnapshots = recorder.snapshots()
        let pendingSnapshots = recordedSnapshots.filter { $0.transferredCount == 0 }

        XCTAssertGreaterThanOrEqual(pendingSnapshots.count, 2)
        XCTAssertGreaterThan(Set(pendingSnapshots.compactMap(\.transferSpeedText)).count, 1)
        XCTAssertEqual(finalSnapshot.transferredCount, 1)
        XCTAssertEqual(finalSnapshot.totalCount, 1)
    }

    func test_photo_library_transfer_service_limits_lan_upload_concurrency_to_three_assets() async {
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
            uploadConcurrencyLimit: 5
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let maxConcurrentUploads = await transferClient.maxConcurrentUploadsObserved()

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertGreaterThan(maxConcurrentUploads, 1)
        XCTAssertLessThanOrEqual(maxConcurrentUploads, 3)
    }

    func test_photo_library_transfer_service_memory_warning_keeps_lan_upload_concurrency_limit() async {
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
        let assetSource = StaticTransferAssetSource(descriptors: descriptors)
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore,
            uploadConcurrencyLimit: 5
        )
        await service.handleMemoryWarning()
        await service.handleMemoryWarning()

        let snapshot = await service.startTransfer(progress: { _ in })
        let maxConcurrentUploads = await transferClient.maxConcurrentUploadsObserved()
        let releasedResourceCount = await assetSource.releaseTransferRunResourcesCount()

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(releasedResourceCount, 3)
        XCTAssertGreaterThan(maxConcurrentUploads, 1)
        XCTAssertLessThanOrEqual(maxConcurrentUploads, 3)
    }

    func test_photo_library_transfer_service_limits_usb_upload_concurrency_when_supported() async {
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
            uploadConcurrencyLimit: 5
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let maxConcurrentUploads = await transferClient.maxConcurrentUploadsObserved()
        let maxConcurrentUSBUploads = await transferClient.maxConcurrentUploadsObserved(for: .usb)

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertGreaterThan(maxConcurrentUploads, 1)
        XCTAssertLessThanOrEqual(maxConcurrentUploads, 5)
        XCTAssertGreaterThan(maxConcurrentUSBUploads, 0)
        XCTAssertLessThanOrEqual(maxConcurrentUSBUploads, 2)
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
            uploadConcurrencyLimit: 5
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let observedTransports = await transferClient.observedPreferredUploadTransports()
        let maxConcurrentUSBUploads = await transferClient.maxConcurrentUploadsObserved(for: .usb)
        let maxConcurrentLANUploads = await transferClient.maxConcurrentUploadsObserved(for: .lan)
        let usbUploads = observedTransports.filter { $0 == .usb }.count
        let lanUploads = observedTransports.filter { $0 == .lan }.count

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(observedTransports.count, descriptors.count)
        XCTAssertGreaterThan(usbUploads, 0)
        XCTAssertGreaterThan(lanUploads, 0)
        XCTAssertLessThanOrEqual(maxConcurrentUSBUploads, 2)
        XCTAssertLessThanOrEqual(maxConcurrentLANUploads, 3)
    }

    func test_photo_library_transfer_service_fetches_assets_in_batches_of_one_hundred() async {
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
        let descriptors = (1 ... 101).map { index in
            TransferAssetDescriptor(
                assetID: String(format: "ph://asset-%03d", index),
                assetVersion: "v\(index)",
                filename: String(format: "IMG_%04d.JPG", index),
                mediaType: "image",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_776_423_610 + index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_776_423_610 + index))
            )
        }
        let assetSource = StaticTransferAssetSource(descriptors: descriptors)
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: RecordingMobileTransferClient(),
            trustedDesktopStore: trustedDesktopStore
        )

        let snapshot = await service.startTransfer(progress: { _ in })
        let batchStarts = await assetSource.batchStarts()
        let batchSizes = await assetSource.batchSizes()

        XCTAssertEqual(snapshot.transferredCount, descriptors.count)
        XCTAssertEqual(snapshot.failedCount, 0)
        XCTAssertEqual(batchStarts, [0, 100])
        XCTAssertEqual(batchSizes, [100, 100])
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
        XCTAssertEqual(snapshot.skippedCount, 2)
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
        let reason = await service.stopTransfer()
        let completedTransferredCount = await transferClient.completedTransferredCount()
        let completedFailedCount = await transferClient.completedFailedCount()
        let completedInterruptionReason = await transferClient.completedInterruptionReason()

        XCTAssertEqual(reason, .stoppedByUser)
        XCTAssertEqual(completedTransferredCount, 0)
        XCTAssertEqual(completedFailedCount, 0)
        XCTAssertEqual(completedInterruptionReason, "stopped_by_user")
    }

    func test_photo_library_transfer_service_does_not_restart_desktop_transfer_after_stop_during_asset_fetch() async {
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
            ],
            initialFetchDelayNanoseconds: 250_000_000
        )
        let transferClient = RecordingMobileTransferClient()
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let startTask = Task {
            await service.startTransfer(progress: { _ in })
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let stopReason = await service.stopTransfer()
        let startSnapshot = await startTask.value
        let startedAssetCount = await transferClient.startedAssetCount()
        let completeSessionCallCount = await transferClient.completeSessionCallCount()

        XCTAssertEqual(stopReason, .stoppedByUser)
        XCTAssertNil(startedAssetCount)
        XCTAssertEqual(completeSessionCallCount, 1)
        XCTAssertEqual(startSnapshot.totalCount, 1)
        XCTAssertEqual(startSnapshot.statusMessage, "Backup stopped. In-flight work was canceled to release resources quickly.")
    }

    func test_photo_library_transfer_service_reports_stop_again_when_stop_happens_during_start_handshake() async {
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
        let transferClient = RecordingMobileTransferClient(startDelayNanoseconds: 250_000_000)
        let service = PhotoLibraryTransferService(
            assetSource: assetSource,
            transferClient: transferClient,
            trustedDesktopStore: trustedDesktopStore
        )

        let startTask = Task {
            await service.startTransfer(progress: { _ in })
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let stopReason = await service.stopTransfer()
        let startSnapshot = await startTask.value
        let startedAssetCount = await transferClient.startedAssetCount()
        let completeSessionCallCount = await transferClient.completeSessionCallCount()
        let completedInterruptionReason = await transferClient.completedInterruptionReason()

        XCTAssertEqual(stopReason, .stoppedByUser)
        XCTAssertEqual(startedAssetCount, 1)
        XCTAssertEqual(completeSessionCallCount, 2)
        XCTAssertEqual(completedInterruptionReason, "stopped_by_user")
        XCTAssertEqual(startSnapshot.totalCount, 1)
        XCTAssertEqual(startSnapshot.statusMessage, "Backup stopped. In-flight work was canceled to release resources quickly.")
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

private actor RecordingMobileTransferClient: ChunkProgressPreferredTransportMobileTransferClient, TransferTransportResolving, TransferLiveTransportResolving, USBTransportConnectivityChecking {
    private var startedCount: Int?
    private let existingAssetIDs: Set<String>
    private let startDelayNanoseconds: UInt64
    private let uploadDelayNanoseconds: UInt64
    private let usbConnected: Bool
    private var resolvedTransport: TransferTransport?
    private var liveTransports: [TransferTransport]?
    private var lookupAssetIDsByBatch: [[String]] = []
    private var uploadedIDs: [String] = []
    private var activeUploadCount = 0
    private var maxConcurrentUploadCount = 0
    private var activeUploadCountByTransport: [String: Int] = [:]
    private var maxConcurrentUploadCountByTransport: [String: Int] = [:]
    private var completedTransferred: Int?
    private var completedFailed: Int?
    private var completedInterruptionReasonValue: String?
    private var completeSessionCalls = 0
    private var preferredUploadTransports: [TransferTransport] = []
    private let simulatedChunkTransferSizes: [Int]
    private let uploadErrorByAssetID: [String: TransferClientError]

    init(
        existingAssetIDs: Set<String> = [],
        usbConnected: Bool = false,
        resolvedTransport: TransferTransport? = nil,
        liveTransports: [TransferTransport]? = nil,
        startDelayNanoseconds: UInt64 = 0,
        uploadDelayNanoseconds: UInt64 = 0,
        simulatedChunkTransferSizes: [Int] = [],
        uploadErrorByAssetID: [String: TransferClientError] = [:]
    ) {
        self.existingAssetIDs = existingAssetIDs
        self.usbConnected = usbConnected
        self.resolvedTransport = resolvedTransport
        self.liveTransports = liveTransports
        self.startDelayNanoseconds = startDelayNanoseconds
        self.uploadDelayNanoseconds = uploadDelayNanoseconds
        self.simulatedChunkTransferSizes = simulatedChunkTransferSizes
        self.uploadErrorByAssetID = uploadErrorByAssetID
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        XCTAssertEqual(desktop.desktopName, "Studio Mac")
        if startDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: startDelayNanoseconds)
        }
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
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
            preferredTransport: nil,
            onChunkTransferred: nil
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse {
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
            preferredTransport: nil,
            onChunkTransferred: onChunkTransferred
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> TransferServerResponse {
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
            preferredTransport: preferredTransport,
            onChunkTransferred: nil
        )
    }

    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse {
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
            preferredTransport: preferredTransport,
            onChunkTransferred: onChunkTransferred
        )
    }

    private func uploadAssetInternal(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?,
        onChunkTransferred: (@Sendable (Int) async -> Void)?
    ) async throws -> TransferServerResponse {
        if let preferredTransport {
            let transportKey = preferredTransport.rawValue
            let activeTransportUploads = activeUploadCountByTransport[transportKey, default: 0] + 1
            activeUploadCountByTransport[transportKey] = activeTransportUploads
            maxConcurrentUploadCountByTransport[transportKey] = max(
                maxConcurrentUploadCountByTransport[transportKey, default: 0],
                activeTransportUploads
            )
        }
        if let preferredTransport {
            preferredUploadTransports.append(preferredTransport)
        }
        activeUploadCount += 1
        maxConcurrentUploadCount = max(maxConcurrentUploadCount, activeUploadCount)
        defer {
            if let preferredTransport {
                let transportKey = preferredTransport.rawValue
                let activeTransportUploads = activeUploadCountByTransport[transportKey, default: 0]
                if activeTransportUploads <= 1 {
                    activeUploadCountByTransport.removeValue(forKey: transportKey)
                } else {
                    activeUploadCountByTransport[transportKey] = activeTransportUploads - 1
                }
            }
            activeUploadCount -= 1
        }
        if let uploadError = uploadErrorByAssetID[asset.descriptor.assetID] {
            throw uploadError
        }
        if uploadDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: uploadDelayNanoseconds)
        }
        if let onChunkTransferred {
            for chunkSize in simulatedChunkTransferSizes {
                await onChunkTransferred(chunkSize)
            }
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
        completeSessionCalls += 1
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

    func resolveLiveTransports(for desktop: TrustedDesktopRecord) async -> [TransferTransport] {
        liveTransports ?? [resolvedTransport ?? desktop.transport]
    }

    func isUSBTransportConnected() async -> Bool {
        usbConnected
    }

    func setResolvedTransport(_ transport: TransferTransport?) {
        resolvedTransport = transport
    }

    func setLiveTransports(_ transports: [TransferTransport]?) {
        liveTransports = transports
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

    func completeSessionCallCount() -> Int {
        completeSessionCalls
    }

    func maxConcurrentUploadsObserved() -> Int {
        maxConcurrentUploadCount
    }

    func maxConcurrentUploadsObserved(for transport: TransferTransport) -> Int {
        maxConcurrentUploadCountByTransport[transport.rawValue, default: 0]
    }

    func observedPreferredUploadTransports() -> [TransferTransport] {
        preferredUploadTransports
    }
}

private actor StaticTransferAssetSource: TransferAssetSource {
    private let descriptors: [TransferAssetDescriptor]
    private let failingAssetIDs: Set<String>
    private let exportedSizeByAssetID: [String: Int]
    private let initialFetchDelayNanoseconds: UInt64
    private var observedBatchStarts: [Int] = []
    private var observedBatchSizes: [Int] = []
    private var releaseResourcesCount = 0
    private var didApplyInitialFetchDelay = false

    init(
        descriptors: [TransferAssetDescriptor],
        failingAssetIDs: Set<String> = [],
        exportedSizeByAssetID: [String: Int] = [:],
        initialFetchDelayNanoseconds: UInt64 = 0
    ) {
        self.descriptors = descriptors
        self.failingAssetIDs = failingAssetIDs
        self.exportedSizeByAssetID = exportedSizeByAssetID
        self.initialFetchDelayNanoseconds = initialFetchDelayNanoseconds
    }

    func fetchAssetBatch(cursor: Int?, batchSize: Int) async throws -> TransferAssetBatch {
        let startIndex = max(cursor ?? 0, 0)
        if !didApplyInitialFetchDelay, startIndex == 0, initialFetchDelayNanoseconds > 0 {
            didApplyInitialFetchDelay = true
            try? await Task.sleep(nanoseconds: initialFetchDelayNanoseconds)
        }
        observedBatchStarts.append(startIndex)
        observedBatchSizes.append(batchSize)
        guard startIndex < descriptors.count else {
            return TransferAssetBatch(
                descriptors: [],
                nextCursor: nil,
                totalCount: descriptors.count
            )
        }

        let endIndex = min(startIndex + max(1, batchSize), descriptors.count)
        let nextCursor: Int? = endIndex < descriptors.count ? endIndex : nil
        return TransferAssetBatch(
            descriptors: Array(descriptors[startIndex ..< endIndex]),
            nextCursor: nextCursor,
            totalCount: descriptors.count
        )
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

    func releaseTransferRunResources() async {
        releaseResourcesCount += 1
    }

    func batchStarts() -> [Int] {
        observedBatchStarts
    }

    func batchSizes() -> [Int] {
        observedBatchSizes
    }

    func releaseTransferRunResourcesCount() -> Int {
        releaseResourcesCount
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

private actor RecordingSpanTelemetryClient: TelemetryClient {
    private var spans: [RecordedSpan] = []

    func withSpan<T: Sendable>(
        name: String,
        attributes: MobileTelemetryAttributes,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        spans.append(RecordedSpan(name: name, attributes: attributes))
        return try await operation()
    }

    func recordedSpans() -> [RecordedSpan] {
        spans
    }
}

private struct RecordedSpan: Equatable {
    let name: String
    let attributes: MobileTelemetryAttributes
}

private func sha1Hex(for data: Data) -> String {
    Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
