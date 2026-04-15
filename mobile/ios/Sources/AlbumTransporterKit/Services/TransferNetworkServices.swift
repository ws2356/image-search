import CryptoKit
import Foundation
import OSLog
import Photos
import UniformTypeIdentifiers

enum TransferProtocol {
    static let schema = "dtis.mobile-transfer.v1"
    static let startPath = "/api/mobile/transfer/start"
    static let existencePath = "/api/mobile/transfer/existence"
    static let assetPath = "/api/mobile/transfer/asset"
    static let completePath = "/api/mobile/transfer/complete"
}

enum TransferAssetStreamProtocol {
    static let chunkSizeBytes = 5 * 1024 * 1024
    static let requestIDQueryField = "request_id"
    static let streamStateQueryField = "stream_state"
    static let streamStateStart = "start"
    static let streamStateChunk = "chunk"
    static let streamStateComplete = "complete"
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

struct TransferExistenceRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var assets: [TransferAssetExistenceCandidate]

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustKey = "trust_key"
        case assets
    }
}

enum TransferResponseStatus: String, Codable, Sendable {
    case accepted
    case stored
    case skipped
    case completed
    case rejected
}

enum TransferExistenceResponseStatus: String, Codable, Sendable {
    case checked
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

struct TransferExistenceResponse: Codable, Sendable {
    var schema: String
    var status: TransferExistenceResponseStatus
    var message: String
    var sessionID: String?
    var deviceUUID: String?
    var matches: [TransferAssetExistenceMatch]

    enum CodingKeys: String, CodingKey {
        case schema
        case status
        case message
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case matches
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

struct TransferAssetExistenceCandidate: Codable, Equatable, Hashable, Sendable {
    var assetID: String
    var contentSHA1: String
    var fileSize: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case contentSHA1 = "sha1"
        case fileSize = "file_size"
        case createdAt = "created_at"
    }
}

struct TransferAssetExistenceMatch: Codable, Equatable, Sendable {
    var assetID: String
    var localRelativePath: String

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case localRelativePath = "local_relative_path"
    }
}

struct ExportedTransferAsset: Sendable {
    var descriptor: TransferAssetDescriptor
    var fileURL: URL
    var mimeType: String?
    var fileSize: Int
    var contentSHA1: String
}

private struct TransferAssetUploadMetadata: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var assetID: String
    var assetVersion: String
    var contentSHA1: String
    var fileSize: Int
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
        case contentSHA1 = "sha1"
        case fileSize = "file_size"
        case filename
        case mediaType = "media_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct TransferAssetStreamStartRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustKey: String
    var assetID: String
    var assetVersion: String
    var contentSHA1: String
    var fileSize: Int
    var filename: String
    var mediaType: String
    var createdAt: Date?
    var updatedAt: Date?
    var streamState = TransferAssetStreamProtocol.streamStateStart
    var chunkSize: Int

    init(metadata: TransferAssetUploadMetadata, chunkSize: Int) {
        sessionID = metadata.sessionID
        deviceUUID = metadata.deviceUUID
        trustKey = metadata.trustKey
        assetID = metadata.assetID
        assetVersion = metadata.assetVersion
        contentSHA1 = metadata.contentSHA1
        fileSize = metadata.fileSize
        filename = metadata.filename
        mediaType = metadata.mediaType
        createdAt = metadata.createdAt
        updatedAt = metadata.updatedAt
        self.chunkSize = chunkSize
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustKey = "trust_key"
        case assetID = "asset_id"
        case assetVersion = "asset_version"
        case contentSHA1 = "sha1"
        case fileSize = "file_size"
        case filename
        case mediaType = "media_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case streamState = "stream_state"
        case chunkSize = "chunk_size"
    }
}

private struct TransferAssetStreamCompleteRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var streamState = TransferAssetStreamProtocol.streamStateComplete

    enum CodingKeys: String, CodingKey {
        case schema
        case streamState = "stream_state"
    }
}

enum TransferAssetChunkStreamError: Error, Sendable {
    case invalidChunkSize
    case streamReadFailed(message: String)
    case sizeMismatch(expected: Int, actual: Int)

    var message: String {
        switch self {
        case .invalidChunkSize:
            return "Desktop transfer requires a positive stream chunk size."
        case .streamReadFailed(let message):
            return "Desktop transfer failed while reading an asset stream chunk: \(message)"
        case .sizeMismatch(let expected, let actual):
            return "Desktop transfer stream size did not match expected asset size (expected \(expected), got \(actual))."
        }
    }
}

enum TransferAssetChunkStreamer {
    static func streamFile(
        fileURL: URL,
        expectedSizeBytes: Int,
        chunkSizeBytes: Int = TransferAssetStreamProtocol.chunkSizeBytes,
        onChunk: @Sendable (Data) async throws -> Void
    ) async throws {
        guard chunkSizeBytes > 0 else {
            throw TransferAssetChunkStreamError.invalidChunkSize
        }
        guard let inputStream = InputStream(url: fileURL) else {
            throw TransferAssetChunkStreamError.streamReadFailed(
                message: "Desktop transfer could not open the asset stream."
            )
        }
        inputStream.open()
        defer {
            inputStream.close()
        }

        var totalBytesRead = 0
        var readBuffer = [UInt8](repeating: 0, count: chunkSizeBytes)
        while true {
            let bytesRead = inputStream.read(&readBuffer, maxLength: readBuffer.count)
            if bytesRead < 0 {
                let streamError = inputStream.streamError?.localizedDescription ?? "unknown stream error"
                throw TransferAssetChunkStreamError.streamReadFailed(message: streamError)
            }
            if bytesRead == 0 {
                break
            }
            totalBytesRead += bytesRead
            try await onChunk(Data(readBuffer[0 ..< bytesRead]))
        }

        guard totalBytesRead == expectedSizeBytes else {
            throw TransferAssetChunkStreamError.sizeMismatch(
                expected: expectedSizeBytes,
                actual: totalBytesRead
            )
        }
    }
}

protocol TransferAssetSource: Sendable {
    func fetchAssets() async throws -> [TransferAssetDescriptor]
    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset
}

protocol MobileTransferClient: Sendable {
    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws
    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch]
    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse
    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse
}

protocol TransferTransportResolving: Sendable {
    func resolveDesktopTransport(for desktop: TrustedDesktopRecord) async -> TransferTransport
}

protocol USBTransportConnectivityChecking: Sendable {
    func isUSBTransportConnected() async -> Bool
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

extension TransferClientError: LocalizedError {
    var errorDescription: String? {
        message
    }
}

protocol TransferSchemaResponse: Decodable {
    var schema: String { get }
    var message: String { get }
}

extension TransferServerResponse: TransferSchemaResponse {}
extension TransferExistenceResponse: TransferSchemaResponse {}

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
        let photosDetail = photosErrorDetail(for: nsError).map { " \($0)" } ?? ""
        return "\(type(of: error)): \(error.localizedDescription) [\(nsError.domain)#\(nsError.code)\(photosDetail)]"
    }

    static func responseBodyPreview(from data: Data) -> String {
        guard !data.isEmpty else {
            return "<empty>"
        }
        let preview = String(decoding: data.prefix(512), as: UTF8.self)
        return preview.isEmpty ? "<binary \(data.count) bytes>" : preview.replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func photosErrorDetail(for error: NSError) -> String? {
        guard error.domain == PHPhotosErrorDomain else {
            return nil
        }

        switch error.code {
        case 3164:
            return "network_access_required"
        case 3169:
            return "network_error"
        case 3301:
            return "operation_interrupted"
        case 3303:
            return "missing_resource"
        case 3305:
            return "not_enough_space"
        case 3306:
            return "request_not_supported_for_asset"
        default:
            return nil
        }
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
            let response = try await postJSON(to: endpoint, body: request, responseType: TransferServerResponse.self)
            TransferDebugLogger.info("Transfer start response \(TransferDebugLogger.responseSummary(response))")
        } catch {
            TransferDebugLogger.error(
                "Transfer start failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            throw error
        }
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        guard !candidates.isEmpty else {
            return [:]
        }

        let request = TransferExistenceRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustKey: desktop.sharedKeyBase64,
            assets: candidates
        )
        let endpoint = transferURL(for: desktop, path: TransferProtocol.existencePath)
        TransferDebugLogger.debug(
            "Checking desktop transfer signatures host=\(endpoint.host ?? "-") session_id=\(desktop.lastSessionID) asset_count=\(candidates.count)"
        )
        do {
            let response = try await postJSON(to: endpoint, body: request, responseType: TransferExistenceResponse.self)
            switch response.status {
            case .checked:
                return Dictionary(uniqueKeysWithValues: response.matches.map { ($0.assetID, $0) })
            case .rejected:
                throw TransferClientError.rejected(message: response.message)
            }
        } catch {
            TransferDebugLogger.error(
                "Desktop transfer signature check failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
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
            contentSHA1: asset.contentSHA1,
            fileSize: asset.fileSize,
            filename: asset.descriptor.filename,
            mediaType: asset.descriptor.mediaType,
            createdAt: asset.descriptor.createdAt,
            updatedAt: asset.descriptor.updatedAt
        )
        let requestID = UUID().uuidString.lowercased()
        let assetSummary = TransferDebugLogger.assetSummary(for: asset.descriptor)
        TransferDebugLogger.debug("Uploading asset \(assetSummary) request_id=\(requestID)")
        do {
            try await startChunkedAssetUpload(
                metadata: metadata,
                desktop: desktop,
                requestID: requestID
            )
            try await TransferAssetChunkStreamer.streamFile(
                fileURL: asset.fileURL,
                expectedSizeBytes: asset.fileSize,
                chunkSizeBytes: TransferAssetStreamProtocol.chunkSizeBytes
            ) { chunkData in
                try await uploadChunkedAssetBytes(
                    chunkData,
                    desktop: desktop,
                    requestID: requestID
                )
            }
            let response = try await finishChunkedAssetUpload(
                desktop: desktop,
                requestID: requestID
            )
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
        } catch let chunkError as TransferAssetChunkStreamError {
            throw TransferClientError.transport(message: chunkError.message)
        } catch {
            TransferDebugLogger.error(
                "Asset upload failed \(assetSummary) error=\(TransferDebugLogger.describe(error))"
            )
            throw error
        }
    }

    private func transferAssetStreamEndpoint(
        desktop: TrustedDesktopRecord,
        requestID: String,
        streamState: String
    ) throws -> URL {
        var components = URLComponents(
            url: transferURL(for: desktop, path: TransferProtocol.assetPath),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: TransferAssetStreamProtocol.requestIDQueryField, value: requestID),
            URLQueryItem(name: TransferAssetStreamProtocol.streamStateQueryField, value: streamState),
        ]
        guard let endpoint = components?.url else {
            throw TransferClientError.transport(message: "Desktop transfer could not build the asset upload URL.")
        }
        return endpoint
    }

    private func startChunkedAssetUpload(
        metadata: TransferAssetUploadMetadata,
        desktop: TrustedDesktopRecord,
        requestID: String
    ) async throws {
        let endpoint = try transferAssetStreamEndpoint(
            desktop: desktop,
            requestID: requestID,
            streamState: TransferAssetStreamProtocol.streamStateStart
        )
        let startRequest = TransferAssetStreamStartRequest(
            metadata: metadata,
            chunkSize: TransferAssetStreamProtocol.chunkSizeBytes
        )
        let response = try await postJSON(
            to: endpoint,
            body: startRequest,
            responseType: TransferServerResponse.self
        )
        guard response.status == .accepted else {
            throw TransferClientError.rejected(message: response.message)
        }
    }

    private func uploadChunkedAssetBytes(
        _ chunkData: Data,
        desktop: TrustedDesktopRecord,
        requestID: String
    ) async throws {
        guard !chunkData.isEmpty else {
            return
        }
        guard chunkData.count <= TransferAssetStreamProtocol.chunkSizeBytes else {
            throw TransferClientError.transport(
                message: "Desktop transfer chunk exceeded the maximum \(TransferAssetStreamProtocol.chunkSizeBytes)-byte limit."
            )
        }
        let endpoint = try transferAssetStreamEndpoint(
            desktop: desktop,
            requestID: requestID,
            streamState: TransferAssetStreamProtocol.streamStateChunk
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await uploadData(
            using: request,
            bodyData: chunkData
        )
        guard response.status == .accepted else {
            throw TransferClientError.rejected(message: response.message)
        }
    }

    private func finishChunkedAssetUpload(
        desktop: TrustedDesktopRecord,
        requestID: String
    ) async throws -> TransferServerResponse {
        let endpoint = try transferAssetStreamEndpoint(
            desktop: desktop,
            requestID: requestID,
            streamState: TransferAssetStreamProtocol.streamStateComplete
        )
        return try await postJSON(
            to: endpoint,
            body: TransferAssetStreamCompleteRequest(),
            responseType: TransferServerResponse.self
        )
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
            let response = try await postJSON(to: endpoint, body: request, responseType: TransferServerResponse.self)
            TransferDebugLogger.info("Transfer completion response \(TransferDebugLogger.responseSummary(response))")
            return response
        } catch {
            TransferDebugLogger.error(
                "Transfer completion failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            throw error
        }
    }

    private func postJSON<RequestBody: Encodable, ResponseBody: TransferSchemaResponse>(
        to endpoint: URL,
        body: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder.pairingEncoder.encode(body)
        return try await execute(request: urlRequest, responseType: responseType)
    }

    private func uploadData(using request: URLRequest, bodyData: Data) async throws -> TransferServerResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: bodyData)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(data: data, response: response, responseType: TransferServerResponse.self)
    }

    private func execute<ResponseBody: TransferSchemaResponse>(
        request: URLRequest,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(data: data, response: response, responseType: responseType)
    }

    private func decodeResponse<ResponseBody: TransferSchemaResponse>(
        data: Data,
        response: URLResponse,
        responseType: ResponseBody.Type
    ) throws -> ResponseBody {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransferClientError.invalidHTTPResponse
        }

        let bodyPreview = TransferDebugLogger.responseBodyPreview(from: data)
        do {
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(responseType, from: data)
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
                "Desktop rejected transfer request http_status=\(httpResponse.statusCode) message=\(decodedResponse.message.replacingOccurrences(of: "\n", with: "\\n"))"
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
        requestOptions.isNetworkAccessAllowed = true
        var lastProgressBucket = -1
        requestOptions.progressHandler = { progress in
            let progressBucket = min(Int(progress * 10), 10)
            guard progressBucket != lastProgressBucket else {
                return
            }
            lastProgressBucket = progressBucket
            TransferDebugLogger.debug(
                "PhotoKit export progress \(TransferDebugLogger.assetSummary(for: descriptor)) progress=\(progressBucket * 10)%"
            )
        }
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
        let contentSHA1: String
        do {
            contentSHA1 = try Self.sha1Hex(for: exportURL)
        } catch {
            TransferDebugLogger.error(
                "Failed to hash exported asset \(TransferDebugLogger.assetSummary(for: descriptor)) error=\(TransferDebugLogger.describe(error))"
            )
            throw TransferClientError.transport(message: "The exported asset could not be hashed for transfer verification.")
        }
        TransferDebugLogger.debug(
            "Exported asset \(TransferDebugLogger.assetSummary(for: descriptor)) bytes=\(fileSize) sha1=\(contentSHA1)"
        )

        return ExportedTransferAsset(
            descriptor: descriptor,
            fileURL: exportURL,
            mimeType: UTType(resource.uniformTypeIdentifier)?.preferredMIMEType,
            fileSize: fileSize,
            contentSHA1: contentSHA1
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
        let preferredTypes: [PHAssetResourceType] = [
            .fullSizePhoto,
            .photo,
            .fullSizeVideo,
            .video,
        ]
        for preferredType in preferredTypes {
            if let resource = resources.first(where: { $0.type == preferredType }) {
                return resource
            }
        }
        return resources.first
    }

    private static func sha1Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = Insecure.SHA1()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
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

private struct PreparedTransferAsset: Sendable {
    let exportedAsset: ExportedTransferAsset
    let existenceCandidate: TransferAssetExistenceCandidate?

    init(exportedAsset: ExportedTransferAsset) {
        self.exportedAsset = exportedAsset
        if let createdAt = exportedAsset.descriptor.createdAt {
            self.existenceCandidate = TransferAssetExistenceCandidate(
                assetID: exportedAsset.descriptor.assetID,
                contentSHA1: exportedAsset.contentSHA1,
                fileSize: exportedAsset.fileSize,
                createdAt: createdAt
            )
        } else {
            self.existenceCandidate = nil
        }
    }
}

actor PhotoLibraryTransferService: TransferService {
    private struct TransferSpeedSample {
        let timestamp: Date
        let bytes: Int
    }

    private static let transferSpeedWindowSeconds: TimeInterval = 10
    private let assetSource: TransferAssetSource
    private let transferClient: MobileTransferClient
    private let transportResolver: (any TransferTransportResolving)?
    private let trustedDesktopStore: TrustedDesktopStore
    private let lookupBatchSize: Int
    private let lookupBatchByteThresholdBytes: Int
    private var transferSpeedSamples: [TransferSpeedSample] = []
    private var stopRequested = false
    private var currentSnapshot: TransferSnapshot?

    init(
        assetSource: TransferAssetSource,
        transferClient: MobileTransferClient,
        trustedDesktopStore: TrustedDesktopStore,
        lookupBatchSize: Int = 32,
        lookupBatchByteThresholdBytes: Int = 100 * 1024 * 1024
    ) {
        self.assetSource = assetSource
        self.transferClient = transferClient
        self.transportResolver = transferClient as? any TransferTransportResolving
        self.trustedDesktopStore = trustedDesktopStore
        self.lookupBatchSize = max(1, lookupBatchSize)
        self.lookupBatchByteThresholdBytes = max(1, lookupBatchByteThresholdBytes)
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        await runTransfer(progress: progress)
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        stopRequested = true
        return .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        await runTransfer(progress: progress)
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            var failedSnapshot = current
            failedSnapshot.statusMessage = "Backup finished on the phone, but the paired desktop record is no longer available."
            currentSnapshot = failedSnapshot
            return failedSnapshot
        }

        do {
            _ = try await transferClient.completeSession(
                desktop: trustedDesktop,
                transferredCount: current.transferredCount,
                failedCount: current.failedCount
            )
            let resolvedTransport = await resolvedTransport(for: trustedDesktop)
            var completedSnapshot = current
            completedSnapshot.transport = resolvedTransport
            completedSnapshot.statusMessage = "Desktop confirmed that this transfer session is complete."
            completedSnapshot.guidanceMessage = "You can return home and start another backup whenever new media appears on the device."
            TransferDebugLogger.info(
                "Desktop confirmed transfer completion session_id=\(trustedDesktop.lastSessionID) transferred=\(current.transferredCount) failed=\(current.failedCount)"
            )
            currentSnapshot = completedSnapshot
            return completedSnapshot
        } catch let error as TransferClientError {
            let resolvedTransport = await resolvedTransport(for: trustedDesktop)
            var failedSnapshot = current
            failedSnapshot.transport = resolvedTransport
            failedSnapshot.statusMessage = error.message
            TransferDebugLogger.error(
                "Transfer completion request failed session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            currentSnapshot = failedSnapshot
            return failedSnapshot
        } catch {
            let resolvedTransport = await resolvedTransport(for: trustedDesktop)
            var failedSnapshot = current
            failedSnapshot.transport = resolvedTransport
            failedSnapshot.statusMessage = error.localizedDescription
            TransferDebugLogger.error(
                "Transfer completion request failed session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            currentSnapshot = failedSnapshot
            return failedSnapshot
        }
    }

    func progressSnapshot() async -> TransferSnapshot? {
        guard var snapshot = currentSnapshot else {
            return nil
        }
        if let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() {
            snapshot.transport = await resolvedTransport(for: trustedDesktop)
        }
        snapshot.transferSpeedText = currentTransferSpeedText()
        currentSnapshot = snapshot
        return snapshot
    }

    private func runTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        stopRequested = false

        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            let failedSnapshot = TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 0,
                transport: .lan,
                etaDescription: nil,
                statusMessage: "No paired desktop record is available for transfer.",
                guidanceMessage: "Pair with the desktop again before starting a backup.",
                isIncompleteLibrary: false
            )
            currentSnapshot = failedSnapshot
            return failedSnapshot
        }

        do {
            let assets = try await assetSource.fetchAssets()
            if assets.isEmpty {
                TransferDebugLogger.warning("Transfer did not start because there are no eligible local assets.")
                let resolvedTransport = await resolvedTransport(for: trustedDesktop)
                let emptySnapshot = TransferSnapshot(
                    transferredCount: 0,
                    totalCount: 0,
                    failedCount: 0,
                    transport: resolvedTransport,
                    etaDescription: nil,
                    statusMessage: "No eligible local photo or video assets are ready for transfer.",
                    guidanceMessage: "Check photo-library access or capture new media, then retry the backup.",
                    isIncompleteLibrary: false
                )
                currentSnapshot = emptySnapshot
                return emptySnapshot
            }

            TransferDebugLogger.info(
                "Starting backup run desktop=\(trustedDesktop.desktopName) session_id=\(trustedDesktop.lastSessionID) asset_count=\(assets.count)"
            )
            try await transferClient.startSession(desktop: trustedDesktop, totalAssets: assets.count)
            resetTransferSpeedWindow()

            var transferredCount = 0
            var failedCount = 0
            var pendingBatch: [PreparedTransferAsset] = []
            var pendingBatchTotalBytes = 0
            let initialTransport = await resolvedTransport(for: trustedDesktop)
            let initialSnapshot = makeProgressSnapshot(
                transport: initialTransport,
                transferredCount: transferredCount,
                totalCount: assets.count,
                failedCount: failedCount
            )
            currentSnapshot = initialSnapshot
            progress(initialSnapshot)

            for (index, asset) in assets.enumerated() {
                if stopRequested {
                    cleanupPreparedAssets(pendingBatch)
                    let currentTransport = await resolvedTransport(for: trustedDesktop)
                    let pausedSnapshot = makePausedSnapshot(
                        transport: currentTransport,
                        transferredCount: transferredCount,
                        totalCount: assets.count,
                        failedCount: failedCount,
                        sessionID: trustedDesktop.lastSessionID
                    )
                    currentSnapshot = pausedSnapshot
                    return pausedSnapshot
                }

                let assetSummary = TransferDebugLogger.assetSummary(for: asset)
                TransferDebugLogger.debug("Preparing asset \(index + 1)/\(assets.count) \(assetSummary)")
                do {
                    let preparedAsset = PreparedTransferAsset(exportedAsset: try await assetSource.exportAsset(asset))
                    if preparedAsset.existenceCandidate == nil {
                        if let pausedSnapshot = await processPreparedBatch(
                            pendingBatch,
                            desktop: trustedDesktop,
                            totalCount: assets.count,
                            transferredCount: &transferredCount,
                            failedCount: &failedCount,
                            progress: progress
                        ) {
                            return pausedSnapshot
                        }
                        pendingBatch.removeAll(keepingCapacity: true)
                        pendingBatchTotalBytes = 0

                        if let pausedSnapshot = await processPreparedBatch(
                            [preparedAsset],
                            desktop: trustedDesktop,
                            totalCount: assets.count,
                            transferredCount: &transferredCount,
                            failedCount: &failedCount,
                            progress: progress
                        ) {
                            return pausedSnapshot
                        }
                        continue
                    }

                    pendingBatch.append(preparedAsset)
                    pendingBatchTotalBytes += max(preparedAsset.exportedAsset.fileSize, 0)
                    if pendingBatch.count >= lookupBatchSize
                        || pendingBatchTotalBytes >= lookupBatchByteThresholdBytes
                    {
                        if let pausedSnapshot = await processPreparedBatch(
                            pendingBatch,
                            desktop: trustedDesktop,
                            totalCount: assets.count,
                            transferredCount: &transferredCount,
                            failedCount: &failedCount,
                            progress: progress
                        ) {
                            return pausedSnapshot
                        }
                        pendingBatch.removeAll(keepingCapacity: true)
                        pendingBatchTotalBytes = 0
                    }
                } catch {
                    failedCount += 1
                    TransferDebugLogger.error(
                        "Transfer failed for \(assetSummary) error=\(TransferDebugLogger.describe(error))"
                    )
                    await recordProgressUpdate(
                        desktop: trustedDesktop,
                        transferredCount: transferredCount,
                        totalCount: assets.count,
                        failedCount: failedCount,
                        progress: progress
                    )
                }
            }

            if stopRequested {
                cleanupPreparedAssets(pendingBatch)
                let currentTransport = await resolvedTransport(for: trustedDesktop)
                let pausedSnapshot = makePausedSnapshot(
                    transport: currentTransport,
                    transferredCount: transferredCount,
                    totalCount: assets.count,
                    failedCount: failedCount,
                    sessionID: trustedDesktop.lastSessionID
                )
                currentSnapshot = pausedSnapshot
                return pausedSnapshot
            }

            if let pausedSnapshot = await processPreparedBatch(
                pendingBatch,
                desktop: trustedDesktop,
                totalCount: assets.count,
                transferredCount: &transferredCount,
                failedCount: &failedCount,
                progress: progress
            ) {
                return pausedSnapshot
            }

            TransferDebugLogger.info(
                "Transfer run finished session_id=\(trustedDesktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount) total=\(assets.count)"
            )
            let completedTransport = await resolvedTransport(for: trustedDesktop)
            let completedSnapshot = TransferSnapshot(
                transferredCount: transferredCount,
                totalCount: assets.count,
                failedCount: failedCount,
                transport: completedTransport,
                transferSpeedText: currentTransferSpeedText(),
                etaDescription: nil,
                statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
                guidanceMessage: failedCount == 0
                    ? "Backup completes automatically after the desktop confirms this transfer session."
                    : "Some items could not be transferred. Start another backup session to retry remaining items, then inspect the MobileTransfer device logs for per-item errors.",
                isIncompleteLibrary: false
            )
            currentSnapshot = completedSnapshot
            return completedSnapshot
        } catch let error as TransferClientError {
            TransferDebugLogger.error(
                "Transfer run failed before asset upload session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            let failedTransport = await resolvedTransport(for: trustedDesktop)
            let failedSnapshot = TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 1,
                transport: failedTransport,
                etaDescription: nil,
                statusMessage: error.message,
                guidanceMessage: "Retry the backup after confirming the paired desktop is reachable on the same local network.",
                isIncompleteLibrary: false
            )
            currentSnapshot = failedSnapshot
            return failedSnapshot
        } catch {
            TransferDebugLogger.error(
                "Transfer run failed before asset upload session_id=\(trustedDesktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            let failedTransport = await resolvedTransport(for: trustedDesktop)
            let failedSnapshot = TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 1,
                transport: failedTransport,
                etaDescription: nil,
                statusMessage: error.localizedDescription,
                guidanceMessage: "Retry the backup after confirming photo-library access and desktop reachability.",
                isIncompleteLibrary: false
            )
            currentSnapshot = failedSnapshot
            return failedSnapshot
        }
    }

    private func processPreparedBatch(
        _ batch: [PreparedTransferAsset],
        desktop: TrustedDesktopRecord,
        totalCount: Int,
        transferredCount: inout Int,
        failedCount: inout Int,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async -> TransferSnapshot? {
        guard !batch.isEmpty else {
            return nil
        }

        let lookupCandidates = batch.compactMap(\.existenceCandidate)
        var matchesByAssetID: [String: TransferAssetExistenceMatch] = [:]
        if !lookupCandidates.isEmpty {
            do {
                matchesByAssetID = try await transferClient.lookupExistingAssets(lookupCandidates, desktop: desktop)
                TransferDebugLogger.debug(
                    "Desktop signature check completed session_id=\(desktop.lastSessionID) requested=\(lookupCandidates.count) matched=\(matchesByAssetID.count)"
                )
            } catch {
                TransferDebugLogger.error(
                    "Desktop signature check failed session_id=\(desktop.lastSessionID) requested=\(lookupCandidates.count) error=\(TransferDebugLogger.describe(error))"
                )
                for preparedAsset in batch {
                    failedCount += 1
                    cleanupExportedAsset(preparedAsset.exportedAsset)
                    await recordProgressUpdate(
                        desktop: desktop,
                        transferredCount: transferredCount,
                        totalCount: totalCount,
                        failedCount: failedCount,
                        progress: progress
                    )
                }
                return nil
            }
        }

        for (index, preparedAsset) in batch.enumerated() {
            let assetSummary = TransferDebugLogger.assetSummary(for: preparedAsset.exportedAsset.descriptor)
            if let existingMatch = matchesByAssetID[preparedAsset.exportedAsset.descriptor.assetID] {
                transferredCount += 1
                cleanupExportedAsset(preparedAsset.exportedAsset)
                TransferDebugLogger.debug(
                    "Skipped upload after desktop signature hit \(assetSummary) local_relative_path=\(existingMatch.localRelativePath)"
                )
                await recordProgressUpdate(
                    desktop: desktop,
                    transferredCount: transferredCount,
                    totalCount: totalCount,
                    failedCount: failedCount,
                    progress: progress
                )
                continue
            }

            if stopRequested {
                cleanupPreparedAssets(Array(batch[index...]))
                let currentTransport = await resolvedTransport(for: desktop)
                let pausedSnapshot = makePausedSnapshot(
                    transport: currentTransport,
                    transferredCount: transferredCount,
                    totalCount: totalCount,
                    failedCount: failedCount,
                    sessionID: desktop.lastSessionID
                )
                currentSnapshot = pausedSnapshot
                return pausedSnapshot
            }

            do {
                let response = try await transferClient.uploadAsset(preparedAsset.exportedAsset, desktop: desktop)
                switch response.status {
                case .stored, .skipped:
                    switch response.status {
                    case .stored:
                        transferredCount += 1
                        recordTransferredBytes(preparedAsset.exportedAsset.fileSize)
                        TransferDebugLogger.debug(
                            "Transferred asset \(assetSummary) response=\(TransferDebugLogger.responseSummary(response))"
                        )
                    case .skipped:
                        transferredCount += 1
                        TransferDebugLogger.debug(
                            "Skipped transfer after desktop confirmation \(assetSummary) response=\(TransferDebugLogger.responseSummary(response))"
                        )
                    case .accepted, .completed, .rejected:
                        break
                    }
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
            cleanupExportedAsset(preparedAsset.exportedAsset)
            await recordProgressUpdate(
                desktop: desktop,
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount,
                progress: progress
            )
        }

        return nil
    }

    private func makePausedSnapshot(
        transport: TransferTransport,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        sessionID: String
    ) -> TransferSnapshot {
        TransferDebugLogger.info(
            "Transfer stop requested session_id=\(sessionID) transferred=\(transferredCount) failed=\(failedCount)"
        )
        return TransferSnapshot(
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            transport: transport,
            transferSpeedText: currentTransferSpeedText(),
            etaDescription: nil,
            statusMessage: "Backup stopped after finishing the current asset upload.",
            guidanceMessage: "Start a new backup session to continue sending the remaining accessible items.",
            isIncompleteLibrary: false
        )
    }

    private func recordProgressUpdate(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async {
        let transport = await resolvedTransport(for: desktop)
        let processedCount = min(transferredCount + failedCount, totalCount)
        TransferDebugLogger.debug(
            "Updated transfer progress processed=\(processedCount) total=\(totalCount) transferred=\(transferredCount) failed=\(failedCount)"
        )
        let updatedSnapshot = makeProgressSnapshot(
            transport: transport,
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount
        )
        currentSnapshot = updatedSnapshot
        progress(updatedSnapshot)
    }

    private func resolvedTransport(for desktop: TrustedDesktopRecord) async -> TransferTransport {
        guard let transportResolver else {
            return desktop.transport
        }
        return await transportResolver.resolveDesktopTransport(for: desktop)
    }

    private func makeProgressSnapshot(
        transport: TransferTransport,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int
    ) -> TransferSnapshot {
        let processedCount = min(transferredCount + failedCount, totalCount)
        return TransferSnapshot(
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            transport: transport,
            transferSpeedText: currentTransferSpeedText(),
            etaDescription: nil,
            statusMessage: totalCount == 0
                ? "Preparing the local media backup with the paired desktop."
                : "Processed \(processedCount) of \(totalCount) items for the paired desktop.",
            guidanceMessage: failedCount == 0
                ? "Keep the app in the foreground while the phone sends items to the desktop."
                : "Some items have failed so far. Let the current run finish, then inspect the MobileTransfer device logs for per-item errors.",
            isIncompleteLibrary: false
        )
    }

    private func cleanupPreparedAssets(_ batch: [PreparedTransferAsset]) {
        for preparedAsset in batch {
            cleanupExportedAsset(preparedAsset.exportedAsset)
        }
    }

    private func cleanupExportedAsset(_ asset: ExportedTransferAsset) {
        try? FileManager.default.removeItem(at: asset.fileURL)
    }

    private func resetTransferSpeedWindow() {
        transferSpeedSamples.removeAll(keepingCapacity: true)
    }

    private func recordTransferredBytes(_ bytes: Int) {
        let normalizedBytes = max(bytes, 0)
        guard normalizedBytes > 0 else {
            return
        }
        let now = Date()
        transferSpeedSamples.append(
            TransferSpeedSample(
                timestamp: now,
                bytes: normalizedBytes
            )
        )
        pruneTransferSpeedSamples(now: now)
    }

    private func currentTransferSpeedText() -> String {
        let now = Date()
        pruneTransferSpeedSamples(now: now)
        let totalBytes = transferSpeedSamples.reduce(0) { partial, sample in
            partial + sample.bytes
        }
        let speedMBps =
            (Double(totalBytes) / 1_048_576.0)
            / Self.transferSpeedWindowSeconds
        return String(format: "%.2f MB/s", speedMBps)
    }

    private func pruneTransferSpeedSamples(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.transferSpeedWindowSeconds)
        transferSpeedSamples.removeAll { sample in
            sample.timestamp < cutoff
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
