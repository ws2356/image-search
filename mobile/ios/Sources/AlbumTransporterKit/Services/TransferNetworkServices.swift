import Foundation
import OSLog
import Photos
import UniformTypeIdentifiers

enum TransferProtocol {
    static let schema = "dtis.mobile-transfer.v1"
    static let startPath = "/api/mobile/transfer/start"
    static let assetPath = "/api/mobile/transfer/asset"
    static let completePath = "/api/mobile/transfer/complete"
}

struct TransferStartRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var totalAssets: Int

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustKey = "trust_key"
        case totalAssets = "total_assets"
    }
}

struct TransferCompleteRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var transferredCount: Int
    var failedCount: Int

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustKey = "trust_key"
        case transferredCount = "transferred_count"
        case failedCount = "failed_count"
    }
}

enum TransferResponseStatus: String, Codable, Sendable {
    case accepted
    case stored
    case skipped
    case completed
    case rejected
}

struct TransferServerResponse: Codable, Sendable {
    var schema: String
    var status: TransferResponseStatus
    var message: String
    var sessionID: String?
    var deviceUUID: String?
    var totalAssets: Int?
    var localRelativePath: String?

    enum CodingKeys: String, CodingKey {
        case schema
        case status
        case message
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case totalAssets = "total_assets"
        case localRelativePath = "local_relative_path"
    }
}

struct TransferAssetDescriptor: Equatable, Sendable {
    var assetID: String
    var assetVersion: String
    var filename: String
    var mediaType: String
    var createdAt: Date?
    var updatedAt: Date?
}

struct ExportedTransferAsset: Sendable {
    var descriptor: TransferAssetDescriptor
    var fileURL: URL
    var mimeType: String?
}

private struct TransferAssetUploadMetadata: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var assetID: String
    var assetVersion: String
    var filename: String
    var mediaType: String
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustKey = "trust_key"
        case assetID = "asset_id"
        case assetVersion = "asset_version"
        case filename
        case mediaType = "media_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

protocol TransferAssetSource: Sendable {
    func fetchAssets() async throws -> [TransferAssetDescriptor]
    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset
}

protocol MobileTransferClient: Sendable {
    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws
    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse
    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse
}

enum TransferClientError: Error, Sendable {
    case invalidHTTPResponse
    case unsupportedResponseSchema
    case rejected(message: String)
    case transport(message: String)
    case decoding(message: String)

    var message: String {
        switch self {
        case .invalidHTTPResponse:
            return "Desktop transfer returned an invalid network response."
        case .unsupportedResponseSchema:
            return "Desktop transfer returned an unsupported response schema."
        case .rejected(let message), .transport(let message), .decoding(let message):
            return message
        }
    }
}

private enum TransferDebugLogger {
    private static let logger = Logger(
        subsystem: "AlbumTransporterKit.MobileFolder",
        category: "MobileTransfer"
    )

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func assetSummary(for descriptor: TransferAssetDescriptor) -> String {
        [
            "asset_id=\(descriptor.assetID)",
            "filename=\(descriptor.filename)",
            "media_type=\(descriptor.mediaType)",
            "asset_version=\(descriptor.assetVersion)",
        ].joined(separator: " ")
    }

    static func responseSummary(_ response: TransferServerResponse) -> String {
        [
            "status=\(response.status.rawValue)",
            "session_id=\(response.sessionID ?? "-")",
            "device_uuid=\(response.deviceUUID ?? "-")",
            "local_relative_path=\(response.localRelativePath ?? "-")",
            "message=\(response.message.replacingOccurrences(of: "\n", with: "\\n"))",
        ].joined(separator: " ")
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(type(of: error)): \(error.localizedDescription) [\(nsError.domain)#\(nsError.code)]"
    }

    static func responseBodyPreview(from data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }
        let preview = String(decoding: data.prefix(512), as: UTF8.self)
        return preview.isEmpty ? "<binary \(data.count) bytes>" : preview.replacingOccurrences(of: "\n", with: "\\n")
    }
}

struct URLSessionMobileTransferClient: MobileTransferClient {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        let request = TransferStartRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            totalAssets: totalAssets
        )
        let endpoint = transferURL(for: desktop, path: TransferProtocol.startPath)
        TransferDebugLogger.info(
            "Starting transfer session host=\(endpoint.host ?? "-") session_id=\(desktop.lastSessionID) total_assets=\(totalAssets)"
        )
        do {
            let response = try await postJSON(to: endpoint, body: request)
            TransferDebugLogger.info("Transfer start response \(TransferDebugLogger.responseSummary(response))")
        } catch {
            TransferDebugLogger.error(
                "Transfer start failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            throw error
        }
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        let metadata = TransferAssetUploadMetadata(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            assetID: asset.descriptor.assetID,
            assetVersion: asset.descriptor.assetVersion,
            filename: asset.descriptor.filename,
            mediaType: asset.descriptor.mediaType,
            createdAt: asset.descriptor.createdAt,
            updatedAt: asset.descriptor.updatedAt
        )
        let encodedMetadata = try JSONEncoder.pairingEncoder.encode(metadata).base64URLEncodedString()
        var components = URLComponents(
            url: transferURL(for: desktop, path: TransferProtocol.assetPath),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "meta", value: encodedMetadata)]
        guard let endpoint = components?.url else {
            throw TransferClientError.transport(message: "Desktop transfer could not build the asset upload URL.")
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let assetSummary = TransferDebugLogger.assetSummary(for: asset.descriptor)
        TransferDebugLogger.debug("Uploading asset \(assetSummary) endpoint=\(endpoint.absoluteString)")
        do {
            let response = try await uploadFile(using: urlRequest, fileURL: asset.fileURL)
            TransferDebugLogger.debug(
                "Upload response for \(assetSummary) \(TransferDebugLogger.responseSummary(response))"
            )
            switch response.status {
            case .stored, .skipped:
                return response
            case .accepted, .completed:
                throw TransferClientError.rejected(message: "Desktop returned an unexpected transfer asset response.")
            case .rejected:
                throw TransferClientError.rejected(message: response.message)
            }
        } catch {
            TransferDebugLogger.error(
                "Asset upload failed \(assetSummary) error=\(TransferDebugLogger.describe(error))"
            )
            throw error
        }
    }

    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse {
        let request = TransferCompleteRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            transferredCount: transferredCount,
            failedCount: failedCount
        )
        let endpoint = transferURL(for: desktop, path: TransferProtocol.completePath)
        TransferDebugLogger.info(
            "Completing transfer session host=\(endpoint.host ?? "-") session_id=\(desktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount)"
        )
        do {
            let response = try await postJSON(to: endpoint, body: request)
            TransferDebugLogger.info("Transfer completion response \(TransferDebugLogger.responseSummary(response))")
            return response
        } catch {
            TransferDebugLogger.error(
                "Transfer completion failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            throw error
        }
    }

    private func postJSON<T: Encodable>(to endpoint: URL, body: T) async throws -> TransferServerResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder.pairingEncoder.encode(body)
        return try await execute(request: urlRequest)
    }

    private func uploadFile(using request: URLRequest, fileURL: URL) async throws -> TransferServerResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(data: data, response: response)
    }

    private func execute(request: URLRequest) async throws -> TransferServerResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(data: data, response: response)
    }

    private func decodeResponse(data: Data, response: URLResponse) throws -> TransferServerResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransferClientError.invalidHTTPResponse
        }

        let bodyPreview = TransferDebugLogger.responseBodyPreview(from: data)
        do {
            let decodedResponse = try JSONDecoder().decode(TransferServerResponse.self, from: data)
            guard decodedResponse.schema == TransferProtocol.schema else {
                TransferDebugLogger.error(
                    "Unsupported transfer response schema http_status=\(httpResponse.statusCode) schema=\(decodedResponse.schema) body=\(bodyPreview)"
                )
                throw TransferClientError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(httpResponse.statusCode) {
                return decodedResponse
            }
            TransferDebugLogger.error(
                "Desktop rejected transfer request http_status=\(httpResponse.statusCode) \(TransferDebugLogger.responseSummary(decodedResponse))"
            )
            throw TransferClientError.rejected(message: decodedResponse.message)
        } catch let error as TransferClientError {
            throw error
        } catch {
            TransferDebugLogger.error(
                "Failed to decode transfer response http_status=\(httpResponse.statusCode) error=\(TransferDebugLogger.describe(error)) body=\(bodyPreview)"
            )
            throw TransferClientError.decoding(message: error.localizedDescription)
        }
    }

    private func transferURL(for desktop: TrustedDesktopRecord, path: String) -> URL {
        var components = URLComponents(url: desktop.endpointURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? desktop.endpointURL
    }
}

actor PhotoLibraryAssetSource: TransferAssetSource {
    func fetchAssets() async throws -> [TransferAssetDescriptor] {
        let authorizationStatus = await requestAuthorizationIfNeeded()
        TransferDebugLogger.info("Photo library authorization status=\(authorizationStatus.transferDescription)")
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            TransferDebugLogger.warning("Photo library access is unavailable for transfer.")
            return []
        }

        let fetchResult = PHAsset.fetchAssets(with: nil)
        var descriptors: [TransferAssetDescriptor] = []
        var skippedResourceCount = 0
        fetchResult.enumerateObjects { asset, _, _ in
            guard let resource = Self.preferredResource(for: asset) else {
                skippedResourceCount += 1
                TransferDebugLogger.debug("Skipping asset without exportable PhotoKit resource asset_id=\(asset.localIdentifier)")
                return
            }
            descriptors.append(
                TransferAssetDescriptor(
                    assetID: asset.localIdentifier,
                    assetVersion: Self.assetVersion(for: asset),
                    filename: resource.originalFilename,
                    mediaType: Self.mediaType(for: asset),
                    createdAt: asset.creationDate,
                    updatedAt: asset.modificationDate ?? asset.creationDate
                )
            )
        }
        TransferDebugLogger.info(
            "Prepared transferable assets count=\(descriptors.count) skipped_without_resource=\(skippedResourceCount)"
        )
        return descriptors
    }

    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [descriptor.assetID], options: nil)
        guard let asset = fetchResult.firstObject,
              let resource = Self.preferredResource(for: asset)
        else {
            TransferDebugLogger.error(
                "Photo library asset is unavailable for export \(TransferDebugLogger.assetSummary(for: descriptor))"
            )
            throw TransferClientError.transport(message: "The selected photo library asset is no longer available.")
        }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
            .appendingPathExtension((descriptor.filename as NSString).pathExtension)

        TransferDebugLogger.debug(
            "Exporting asset \(TransferDebugLogger.assetSummary(for: descriptor)) resource_type=\(resource.type.rawValue) uti=\(resource.uniformTypeIdentifier)"
        )
        let requestOptions = PHAssetResourceRequestOptions()
        requestOptions.isNetworkAccessAllowed = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: exportURL,
                options: requestOptions
            ) { error in
                if let error {
                    TransferDebugLogger.error(
                        "PhotoKit export failed for \(TransferDebugLogger.assetSummary(for: descriptor)) error=\(TransferDebugLogger.describe(error))"
                    )
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }

        let fileSize = (try? exportURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        TransferDebugLogger.debug(
            "Exported asset \(TransferDebugLogger.assetSummary(for: descriptor)) bytes=\(fileSize)"
        )

        return ExportedTransferAsset(
            descriptor: descriptor,
            fileURL: exportURL,
            mimeType: UTType(resource.uniformTypeIdentifier)?.preferredMIMEType
        )
    }

    private func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func preferredResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { resource in
            switch resource.type {
            case .photo, .fullSizePhoto, .video, .fullSizeVideo:
                return true
            default:
                return false
            }
        } ?? resources.first
    }

    private static func assetVersion(for asset: PHAsset) -> String {
        let timestamp = asset.modificationDate ?? asset.creationDate ?? Date(timeIntervalSince1970: 0)
        return [
            PairingDateCodec.string(from: timestamp),
            "\(asset.pixelWidth)x\(asset.pixelHeight)",
            String(Int(asset.duration * 1000)),
        ].joined(separator: "|")
    }

    private static func mediaType(for asset: PHAsset) -> String {
        switch asset.mediaType {
        case .video:
            return "video"
        default:
            return "image"
        }
    }
}

actor PhotoLibraryTransferService: TransferService {
    private let assetSource: TransferAssetSource
    private let transferClient: MobileTransferClient
    private let trustedDesktopStore: TrustedDesktopStore
    private var stopRequested = false

    init(
        assetSource: TransferAssetSource,
        transferClient: MobileTransferClient,
        trustedDesktopStore: TrustedDesktopStore
    ) {
        self.assetSource = assetSource
        self.transferClient = transferClient
        self.trustedDesktopStore = trustedDesktopStore
    }

    func startTransfer() async -> TransferSnapshot {
        await runTransfer()
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        stopRequested = true
        return .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot) async -> TransferSnapshot {
        await runTransfer()
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            var failedSnapshot = current
            failedSnapshot.statusMessage = "Backup finished on the phone, but the paired desktop record is no longer available."
            return failedSnapshot
        }

        do {
            _ = try await transferClient.completeSession(
                desktop: trustedDesktop,
                transferredCount: current.transferredCount,
                failedCount: current.failedCount
            )
            var completedSnapshot = current
            completedSnapshot.statusMessage = "Desktop confirmed that this transfer session is complete."
            completedSnapshot.guidanceMessage = "You can return home and start another backup whenever new media appears on the device."
            TransferDebugLogger.info(
                "Desktop confirmed transfer completion session_id=\(trustedDesktop.lastSessionID) transferred=\(current.transferredCount) failed=\(current.failedCount)"
            )
            return completedSnapshot
        } catch let error as TransferClientError {
            var failedSnapshot = current
            failedSnapshot.statusMessage = error.message
            TransferDebugLogger.error(
                "Transfer completion request failed session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            return failedSnapshot
        } catch {
            var failedSnapshot = current
            failedSnapshot.statusMessage = error.localizedDescription
            TransferDebugLogger.error(
                "Transfer completion request failed session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            return failedSnapshot
        }
    }

    private func runTransfer() async -> TransferSnapshot {
        stopRequested = false

        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            return TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 0,
                transport: .lan,
                etaDescription: nil,
                statusMessage: "No paired desktop record is available for transfer.",
                guidanceMessage: "Pair with the desktop again before starting a backup.",
                isIncompleteLibrary: false
            )
        }

        do {
            let assets = try await assetSource.fetchAssets()
            if assets.isEmpty {
                TransferDebugLogger.warning("Transfer did not start because there are no eligible local assets.")
                return TransferSnapshot(
                    transferredCount: 0,
                    totalCount: 0,
                    failedCount: 0,
                    transport: trustedDesktop.transport,
                    etaDescription: nil,
                    statusMessage: "No eligible local photo or video assets are ready for transfer.",
                    guidanceMessage: "Check photo-library access or capture new media, then retry the backup.",
                    isIncompleteLibrary: false
                )
            }

            TransferDebugLogger.info(
                "Starting backup run desktop=\(trustedDesktop.desktopName) session_id=\(trustedDesktop.lastSessionID) asset_count=\(assets.count)"
            )
            try await transferClient.startSession(desktop: trustedDesktop, totalAssets: assets.count)

            var transferredCount = 0
            var failedCount = 0
            for (index, asset) in assets.enumerated() {
                if stopRequested {
                    TransferDebugLogger.info(
                        "Transfer paused session_id=\(trustedDesktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount)"
                    )
                    return TransferSnapshot(
                        transferredCount: transferredCount,
                        totalCount: assets.count,
                        failedCount: failedCount,
                        transport: trustedDesktop.transport,
                        etaDescription: nil,
                        statusMessage: "Backup paused after finishing the current asset upload.",
                        guidanceMessage: "Resume to continue sending the remaining accessible items.",
                        isIncompleteLibrary: false
                    )
                }

                let assetSummary = TransferDebugLogger.assetSummary(for: asset)
                TransferDebugLogger.debug("Processing asset \(index + 1)/\(assets.count) \(assetSummary)")
                do {
                    let exportedAsset = try await assetSource.exportAsset(asset)
                    defer { try? FileManager.default.removeItem(at: exportedAsset.fileURL) }
                    let response = try await transferClient.uploadAsset(exportedAsset, desktop: trustedDesktop)
                    switch response.status {
                    case .stored, .skipped:
                        transferredCount += 1
                        TransferDebugLogger.debug(
                            "Transferred asset \(assetSummary) response=\(TransferDebugLogger.responseSummary(response))"
                        )
                    case .accepted, .completed, .rejected:
                        failedCount += 1
                        TransferDebugLogger.error(
                            "Unexpected asset response for \(assetSummary) response=\(TransferDebugLogger.responseSummary(response))"
                        )
                    }
                } catch {
                    failedCount += 1
                    TransferDebugLogger.error(
                        "Transfer failed for \(assetSummary) error=\(TransferDebugLogger.describe(error))"
                    )
                }
            }

            TransferDebugLogger.info(
                "Transfer run finished session_id=\(trustedDesktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount) total=\(assets.count)"
            )
            return TransferSnapshot(
                transferredCount: transferredCount,
                totalCount: assets.count,
                failedCount: failedCount,
                transport: trustedDesktop.transport,
                etaDescription: nil,
                statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
                guidanceMessage: failedCount == 0
                    ? "Tap Finish Backup after the desktop confirms the transfer session is complete."
                    : "Some items could not be transferred. Retry Resume Backup to send any remaining items again, then inspect the MobileTransfer device logs for per-item errors.",
                isIncompleteLibrary: false
            )
        } catch let error as TransferClientError {
            TransferDebugLogger.error(
                "Transfer run failed before asset upload session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            return TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 1,
                transport: trustedDesktop.transport,
                etaDescription: nil,
                statusMessage: error.message,
                guidanceMessage: "Retry the backup after confirming the paired desktop is reachable on the same local network.",
                isIncompleteLibrary: false
            )
        } catch {
            TransferDebugLogger.error(
                "Transfer run failed before asset upload session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            return TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 1,
                transport: trustedDesktop.transport,
                etaDescription: nil,
                statusMessage: error.localizedDescription,
                guidanceMessage: "Retry the backup after confirming photo-library access and desktop reachability.",
                isIncompleteLibrary: false
            )
        }
    }
}

private extension PHAuthorizationStatus {
    var transferDescription: String {
        switch self {
        case .authorized:
            return "authorized"
        case .limited:
            return "limited"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
