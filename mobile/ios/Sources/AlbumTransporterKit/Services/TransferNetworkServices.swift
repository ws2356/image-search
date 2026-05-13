@preconcurrency import AVFoundation
import CryptoKit
import Darwin
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

enum CapabilityExchangeProtocol {
    static let schema = "dtis.mobile-capabilities.v1"
    static let exchangePath = "/api/mobile/capabilities/exchange"
}

enum UpdatePromptProtocol {
    static let schema = "dtis.mobile-update.v1"
    static let promptPath = "/api/mobile/update/prompt"
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
    var trustProof: String
    var totalAssets: Int

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustProof = "trust_proof"
        case totalAssets = "total_assets"
    }
}

struct TransferCompleteRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustProof: String
    var transferredCount: Int
    var failedCount: Int
    var interruptionReason: String? = nil

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustProof = "trust_proof"
        case transferredCount = "transferred_count"
        case failedCount = "failed_count"
        case interruptionReason = "interruption_reason"
    }
}

struct TransferExistenceRequest: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustProof: String
    var assets: [TransferAssetExistenceCandidate]

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustProof = "trust_proof"
        case assets
    }
}

struct CapabilityExchangeRequest: Codable, Sendable {
    var schema = CapabilityExchangeProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustProof: String
    var capabilities: [String: Int]

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustProof = "trust_proof"
        case capabilities
    }
}

struct UpdatePromptRequest: Codable, Sendable {
    var schema = UpdatePromptProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustProof: String
    var required: Bool
    var bodyText: String?
    var updateDestination: String?

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case trustProof = "trust_proof"
        case required
        case bodyText = "body_text"
        case updateDestination = "update_destination"
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

enum CapabilityExchangeResponseStatus: String, Codable, Sendable {
    case accepted
    case rejected
}

enum UpdatePromptResponseStatus: String, Codable, Sendable {
    case accepted
    case rejected
}

enum TransferFailureCode: String, Codable, Sendable {
    case diskFull = "disk_full"
}

struct TransferServerResponse: Codable, Sendable {
    var schema: String
    var status: TransferResponseStatus
    var message: String
    var sessionID: String?
    var deviceUUID: String?
    var totalAssets: Int?
    var localRelativePath: String?
    var failureCode: TransferFailureCode? = nil

    enum CodingKeys: String, CodingKey {
        case schema
        case status
        case message
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case totalAssets = "total_assets"
        case localRelativePath = "local_relative_path"
        case failureCode = "failure_code"
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

struct CapabilityExchangeResponse: Codable, Sendable, TransferSchemaResponse {
    var schema: String
    var status: CapabilityExchangeResponseStatus
    var message: String
    var sessionID: String?
    var deviceUUID: String?
    var capabilities: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case schema
        case status
        case message
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case capabilities
    }
}

struct UpdatePromptResponse: Codable, Sendable, TransferSchemaResponse {
    var schema: String
    var status: UpdatePromptResponseStatus
    var message: String
    var sessionID: String?
    var deviceUUID: String?
    var required: Bool?

    enum CodingKeys: String, CodingKey {
        case schema
        case status
        case message
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
        case required
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

struct TransferAssetBatch: Sendable {
    var descriptors: [TransferAssetDescriptor]
    var nextCursor: Int?
    var totalCount: Int
}

private struct TransferAssetUploadMetadata: Codable, Sendable {
    var schema = TransferProtocol.schema
    var sessionID: String
    var deviceUUID: String
    var trustProof: String
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
        case trustProof = "trust_proof"
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
    var trustProof: String
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
        trustProof = metadata.trustProof
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
        case trustProof = "trust_proof"
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
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw TransferAssetChunkStreamError.streamReadFailed(
                message: TransferDebugLogger.describe(error)
            )
        }
        defer {
            try? fileHandle.close()
        }

        var totalBytesRead = 0
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do {
                chunk = try fileHandle.read(upToCount: chunkSizeBytes) ?? Data()
            } catch {
                throw TransferAssetChunkStreamError.streamReadFailed(
                    message: TransferDebugLogger.describe(error)
                )
            }
            if chunk.isEmpty {
                break
            }
            totalBytesRead += chunk.count
            try Task.checkCancellation()
            try await onChunk(chunk)
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
    func fetchAssetBatch(cursor: Int?, batchSize: Int) async throws -> TransferAssetBatch
    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset
    func releaseTransferRunResources() async
}

extension TransferAssetSource {
    func releaseTransferRunResources() async {}
}

protocol MobileTransferClient: Sendable {
    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws
    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch]
    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse
    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse
}

protocol MobileCapabilityExchangeClient: Sendable {
    func exchangeCapabilities(
        _ mobileCapabilities: [String: Int],
        desktop: TrustedDesktopRecord
    ) async throws -> CapabilityExchangeResponse
}

protocol MobileUpdatePromptClient: Sendable {
    func sendUpdatePrompt(
        required: Bool,
        bodyText: String?,
        updateDestination: String?,
        desktop: TrustedDesktopRecord
    ) async throws -> UpdatePromptResponse
}

protocol PreferredTransportMobileTransferClient: MobileTransferClient {
    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> [String: TransferAssetExistenceMatch]
    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?
    ) async throws -> TransferServerResponse
}

protocol ChunkProgressMobileTransferClient: MobileTransferClient {
    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse
}

protocol ChunkProgressPreferredTransportMobileTransferClient: PreferredTransportMobileTransferClient {
    func uploadAsset(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        preferredTransport: TransferTransport?,
        onChunkTransferred: @escaping @Sendable (Int) async -> Void
    ) async throws -> TransferServerResponse
}

protocol TransferTransportResolving: Sendable {
    func resolveDesktopTransport(for desktop: TrustedDesktopRecord) async -> TransferTransport
}

protocol TransferLiveTransportResolving: Sendable {
    func resolveLiveTransports(for desktop: TrustedDesktopRecord) async -> [TransferTransport]
}

protocol USBTransportConnectivityChecking: Sendable {
    func isUSBTransportConnected() async -> Bool
}

protocol USBTransportForegroundRecovering: Sendable {
    func recoverUSBTransportAfterForegroundResume(for desktop: TrustedDesktopRecord) async
}

enum TransferClientError: Error, Sendable {
    case invalidHTTPResponse
    case unsupportedResponseSchema
    case rejected(message: String)
    case terminalFailure(code: TransferFailureCode, message: String)
    case transport(message: String)
    case decoding(message: String)

    var message: String {
        switch self {
        case .invalidHTTPResponse:
            return "Desktop transfer returned an invalid network response."
        case .unsupportedResponseSchema:
            return "Desktop transfer returned an unsupported response schema."
        case .rejected(let message), .terminalFailure(_, let message), .transport(let message), .decoding(let message):
            return message
        }
    }

    var terminalFailureCode: TransferFailureCode? {
        guard case .terminalFailure(let code, _) = self else {
            return nil
        }
        return code
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

extension TransferServerResponse {
    var rejectionError: TransferClientError {
        guard let failureCode else {
            return .rejected(message: message)
        }
        return .terminalFailure(code: failureCode, message: message)
    }
}

enum TransferTrustProof {
    private static let context = "dtis.mobile-trust-proof.v1"

    static func make(
        trustKey: String,
        purpose: String,
        schema: String,
        sessionID: String,
        deviceUUID: String
    ) -> String {
        let material = Data(
            [
                context,
                purpose,
                schema,
                sessionID,
                deviceUUID,
            ].joined(separator: "\n").utf8
        )
        let proof = HMAC<SHA256>.authenticationCode(
            for: material,
            using: SymmetricKey(data: Data(trustKey.utf8))
        )
        return Data(proof).base64URLEncodedString()
    }
}

enum TransferTrustProofPurpose {
    static let transferStart = "transfer.start"
    static let transferExistence = "transfer.existence"
    static let transferAsset = "transfer.asset"
    static let transferComplete = "transfer.complete"
    static let capabilityExchange = "capabilities.exchange"
    static let updatePrompt = "update.prompt"
}

private func normalizedSupportedCapabilityFlags(_ capabilityFlags: [String: Int]) -> [String: Int] {
    var normalizedFlags: [String: Int] = [:]
    for (capabilityName, capabilityValue) in capabilityFlags {
        let trimmedCapabilityName = capabilityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCapabilityName.isEmpty, capabilityValue == 1 else {
            continue
        }
        normalizedFlags[trimmedCapabilityName] = 1
    }
    return normalizedFlags
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

private actor TransferSessionURLSessionStore {
    private var sessionsBySessionID: [String: URLSession] = [:]

    func session(for sessionID: String) -> URLSession {
        if let session = sessionsBySessionID[sessionID] {
            return session
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        sessionsBySessionID[sessionID] = session
        return session
    }

    func release(sessionID: String) async {
        guard let session = sessionsBySessionID.removeValue(forKey: sessionID) else {
            return
        }
        await withCheckedContinuation { continuation in
            session.reset {
                continuation.resume()
            }
        }
        session.invalidateAndCancel()
    }
}

struct URLSessionMobileTransferClient: MobileTransferClient, ChunkProgressMobileTransferClient, MobileCapabilityExchangeClient, MobileUpdatePromptClient {
    private let defaultSession: URLSession
    private let telemetryClient: TelemetryClient
    private let usePerBackupEphemeralSession: Bool
    private let sessionStore: TransferSessionURLSessionStore

    init(
        session: URLSession = .shared,
        telemetryClient: TelemetryClient = NoOpTelemetryClient(),
        usePerBackupEphemeralSession: Bool = false
    ) {
        self.defaultSession = session
        self.telemetryClient = telemetryClient
        self.usePerBackupEphemeralSession = usePerBackupEphemeralSession
        self.sessionStore = TransferSessionURLSessionStore()
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        let activeSession = await activeSession(for: desktop)
        var request = TransferStartRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            totalAssets: totalAssets
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferStart,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let endpoint = transferURL(for: desktop, path: TransferProtocol.startPath)
        TransferDebugLogger.info(
            "Starting transfer session host=\(endpoint.host ?? "-") session_id=\(desktop.lastSessionID) total_assets=\(totalAssets)"
        )
        do {
            let response = try await postJSON(
                to: endpoint,
                body: request,
                responseType: TransferServerResponse.self,
                using: activeSession
            )
            TransferDebugLogger.info("Transfer start response \(TransferDebugLogger.responseSummary(response))")
        } catch {
            TransferDebugLogger.error(
                "Transfer start failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            await releaseSession(for: desktop)
            throw error
        }
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        let activeSession = await activeSession(for: desktop)
        guard !candidates.isEmpty else {
            return [:]
        }

        var request = TransferExistenceRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            assets: candidates
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferExistence,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let endpoint = transferURL(for: desktop, path: TransferProtocol.existencePath)
        TransferDebugLogger.debug(
            "Checking desktop transfer signatures host=\(endpoint.host ?? "-") session_id=\(desktop.lastSessionID) asset_count=\(candidates.count)"
        )
        do {
            let response = try await postJSON(
                to: endpoint,
                body: request,
                responseType: TransferExistenceResponse.self,
                using: activeSession
            )
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

    func exchangeCapabilities(
        _ mobileCapabilities: [String: Int],
        desktop: TrustedDesktopRecord
    ) async throws -> CapabilityExchangeResponse {
        let activeSession = await activeSession(for: desktop)
        var request = CapabilityExchangeRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            capabilities: normalizedSupportedCapabilityFlags(mobileCapabilities)
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.capabilityExchange,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let endpoint = transferURL(for: desktop, path: CapabilityExchangeProtocol.exchangePath)
        let response = try await postJSON(
            to: endpoint,
            body: request,
            responseType: CapabilityExchangeResponse.self,
            expectedSchema: CapabilityExchangeProtocol.schema,
            using: activeSession
        )
        switch response.status {
        case .accepted:
            return response
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        }
    }

    func sendUpdatePrompt(
        required: Bool,
        bodyText: String?,
        updateDestination: String?,
        desktop: TrustedDesktopRecord
    ) async throws -> UpdatePromptResponse {
        let activeSession = await activeSession(for: desktop)
        var request = UpdatePromptRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            required: required,
            bodyText: bodyText,
            updateDestination: updateDestination
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.updatePrompt,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let endpoint = transferURL(for: desktop, path: UpdatePromptProtocol.promptPath)
        let response = try await postJSON(
            to: endpoint,
            body: request,
            responseType: UpdatePromptResponse.self,
            expectedSchema: UpdatePromptProtocol.schema,
            using: activeSession
        )
        switch response.status {
        case .accepted:
            return response
        case .rejected:
            throw TransferClientError.rejected(message: response.message)
        }
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        try await uploadAssetInternal(
            asset,
            desktop: desktop,
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
            onChunkTransferred: onChunkTransferred
        )
    }

    private func uploadAssetInternal(
        _ asset: ExportedTransferAsset,
        desktop: TrustedDesktopRecord,
        onChunkTransferred: (@Sendable (Int) async -> Void)?
    ) async throws -> TransferServerResponse {
        let activeSession = await activeSession(for: desktop)
        try Task.checkCancellation()
        var metadata = TransferAssetUploadMetadata(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            assetID: asset.descriptor.assetID,
            assetVersion: asset.descriptor.assetVersion,
            contentSHA1: asset.contentSHA1,
            fileSize: asset.fileSize,
            filename: asset.descriptor.filename,
            mediaType: asset.descriptor.mediaType,
            createdAt: asset.descriptor.createdAt,
            updatedAt: asset.descriptor.updatedAt
        )
        metadata.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferAsset,
            schema: metadata.schema,
            sessionID: metadata.sessionID,
            deviceUUID: metadata.deviceUUID
        )
        let requestID = UUID().uuidString.lowercased()
        let assetSummary = TransferDebugLogger.assetSummary(for: asset.descriptor)
        TransferDebugLogger.debug("Uploading asset \(assetSummary) request_id=\(requestID)")
        do {
            try await startChunkedAssetUpload(
                metadata: metadata,
                desktop: desktop,
                requestID: requestID,
                session: activeSession
            )
            if asset.fileSize <= TransferAssetStreamProtocol.chunkSizeBytes {
                try await uploadChunkedAssetFile(
                    asset.fileURL,
                    desktop: desktop,
                    requestID: requestID,
                    session: activeSession
                )
                if let onChunkTransferred {
                    await onChunkTransferred(asset.fileSize)
                }
            } else {
                try await TransferAssetChunkStreamer.streamFile(
                    fileURL: asset.fileURL,
                    expectedSizeBytes: asset.fileSize,
                    chunkSizeBytes: TransferAssetStreamProtocol.chunkSizeBytes
                ) { chunkData in
                    try Task.checkCancellation()
                    try await uploadChunkedAssetBytes(
                        chunkData,
                        desktop: desktop,
                        requestID: requestID,
                        session: activeSession
                    )
                    if let onChunkTransferred {
                        await onChunkTransferred(chunkData.count)
                    }
                }
            }
            let response = try await finishChunkedAssetUpload(
                desktop: desktop,
                requestID: requestID,
                session: activeSession
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
                throw response.rejectionError
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
        requestID: String,
        session: URLSession
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
            responseType: TransferServerResponse.self,
            using: session
        )
        guard response.status == .accepted else {
            throw response.rejectionError
        }
    }

    private func uploadChunkedAssetBytes(
        _ chunkData: Data,
        desktop: TrustedDesktopRecord,
        requestID: String,
        session: URLSession
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
            bodyData: chunkData,
            session: session
        )
        guard response.status == .accepted else {
            throw response.rejectionError
        }
    }

    private func uploadChunkedAssetFile(
        _ fileURL: URL,
        desktop: TrustedDesktopRecord,
        requestID: String,
        session: URLSession
    ) async throws {
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
        let response = try await uploadFile(
            using: request,
            fileURL: fileURL,
            session: session
        )
        guard response.status == .accepted else {
            throw response.rejectionError
        }
    }

    private func finishChunkedAssetUpload(
        desktop: TrustedDesktopRecord,
        requestID: String,
        session: URLSession
    ) async throws -> TransferServerResponse {
        let endpoint = try transferAssetStreamEndpoint(
            desktop: desktop,
            requestID: requestID,
            streamState: TransferAssetStreamProtocol.streamStateComplete
        )
        return try await postJSON(
            to: endpoint,
            body: TransferAssetStreamCompleteRequest(),
            responseType: TransferServerResponse.self,
            using: session
        )
    }

    func completeSession(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int,
        interruptionReason: String?
    ) async throws -> TransferServerResponse {
        let activeSession = await activeSession(for: desktop)
        var request = TransferCompleteRequest(
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            trustProof: "",
            transferredCount: transferredCount,
            failedCount: failedCount,
            interruptionReason: interruptionReason
        )
        request.trustProof = TransferTrustProof.make(
            trustKey: desktop.sharedKeyBase64,
            purpose: TransferTrustProofPurpose.transferComplete,
            schema: request.schema,
            sessionID: request.sessionID,
            deviceUUID: request.deviceUUID
        )
        let endpoint = transferURL(for: desktop, path: TransferProtocol.completePath)
        TransferDebugLogger.info(
            "Completing transfer session host=\(endpoint.host ?? "-") session_id=\(desktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount)"
        )
        do {
            let response = try await postJSON(
                to: endpoint,
                body: request,
                responseType: TransferServerResponse.self,
                using: activeSession
            )
            TransferDebugLogger.info("Transfer completion response \(TransferDebugLogger.responseSummary(response))")
            await releaseSession(for: desktop)
            return response
        } catch {
            TransferDebugLogger.error(
                "Transfer completion failed session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            await releaseSession(for: desktop)
            throw error
        }
    }

    private func postJSON<RequestBody: Encodable, ResponseBody: TransferSchemaResponse>(
        to endpoint: URL,
        body: RequestBody,
        responseType: ResponseBody.Type,
        expectedSchema: String = TransferProtocol.schema,
        using session: URLSession
    ) async throws -> ResponseBody {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try await encodeRequestBody(body)
        return try await execute(
            request: urlRequest,
            responseType: responseType,
            expectedSchema: expectedSchema,
            using: session
        )
    }

    private func uploadData(
        using request: URLRequest,
        bodyData: Data,
        session: URLSession
    ) async throws -> TransferServerResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: bodyData)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(data: data, response: response, responseType: TransferServerResponse.self)
    }

    private func uploadFile(
        using request: URLRequest,
        fileURL: URL,
        session: URLSession
    ) async throws -> TransferServerResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(data: data, response: response, responseType: TransferServerResponse.self)
    }

    private func execute<ResponseBody: TransferSchemaResponse>(
        request: URLRequest,
        responseType: ResponseBody.Type,
        expectedSchema: String = TransferProtocol.schema,
        using session: URLSession
    ) async throws -> ResponseBody {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TransferClientError.transport(message: error.localizedDescription)
        }
        return try decodeResponse(
            data: data,
            response: response,
            responseType: responseType,
            expectedSchema: expectedSchema
        )
    }

    private func activeSession(for desktop: TrustedDesktopRecord) async -> URLSession {
        guard usePerBackupEphemeralSession else {
            return defaultSession
        }
        return await sessionStore.session(for: desktop.lastSessionID)
    }

    private func releaseSession(for desktop: TrustedDesktopRecord) async {
        guard usePerBackupEphemeralSession else {
            return
        }
        await sessionStore.release(sessionID: desktop.lastSessionID)
    }

    private func decodeResponse<ResponseBody: TransferSchemaResponse>(
        data: Data,
        response: URLResponse,
        responseType: ResponseBody.Type,
        expectedSchema: String = TransferProtocol.schema
    ) throws -> ResponseBody {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransferClientError.invalidHTTPResponse
        }

        let bodyPreview = TransferDebugLogger.responseBodyPreview(from: data)
        do {
            let decodedResponse = try JSONDecoder.pairingDecoder.decode(responseType, from: data)
            guard decodedResponse.schema == expectedSchema else {
                TransferDebugLogger.error(
                    "Unsupported transfer response schema http_status=\(httpResponse.statusCode) schema=\(decodedResponse.schema) expected=\(expectedSchema) body=\(bodyPreview)"
                )
                throw TransferClientError.unsupportedResponseSchema
            }

            if (200 ..< 300).contains(httpResponse.statusCode) {
                return decodedResponse
            }
            TransferDebugLogger.error(
                "Desktop rejected transfer request http_status=\(httpResponse.statusCode) message=\(decodedResponse.message.replacingOccurrences(of: "\n", with: "\\n"))"
            )
            if let transferResponse = decodedResponse as? TransferServerResponse {
                throw transferResponse.rejectionError
            }
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

    private func encodeRequestBody<RequestBody: Encodable>(_ body: RequestBody) async throws -> Data {
        let encodedBody = try JSONEncoder.pairingEncoder.encode(body)
        guard var bodyValue = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] else {
            throw TransferClientError.transport(message: "Desktop transfer request body could not be encoded.")
        }
        for (key, value) in traceContextPayloadFields(await telemetryClient.currentTraceContext()) {
            bodyValue[key] = value
        }
        guard JSONSerialization.isValidJSONObject(bodyValue) else {
            throw TransferClientError.transport(message: "Desktop transfer request body is invalid.")
        }
        return try JSONSerialization.data(withJSONObject: bodyValue, options: [])
    }
}

actor PhotoLibraryAssetSource: TransferAssetSource {
    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }

    private struct PreparedExportFile {
        let fileURL: URL
        let mimeType: String?
        let filename: String
    }

    private var cachedFetchResult: PHFetchResult<PHAsset>?

    func fetchAssetBatch(cursor: Int?, batchSize: Int) async throws -> TransferAssetBatch {
        guard batchSize > 0 else {
            throw TransferClientError.transport(message: "Asset batch size must be greater than zero.")
        }
        guard let fetchResult = try await fetchResultForTransfer(refresh: cursor == nil) else {
            return TransferAssetBatch(descriptors: [], nextCursor: nil, totalCount: 0)
        }

        let totalCount = fetchResult.count
        let startIndex = max(cursor ?? 0, 0)
        guard startIndex < totalCount else {
            return TransferAssetBatch(descriptors: [], nextCursor: nil, totalCount: totalCount)
        }

        let endIndex = min(startIndex + batchSize, totalCount)
        var descriptors: [TransferAssetDescriptor] = []
        descriptors.reserveCapacity(endIndex - startIndex)
        for index in startIndex ..< endIndex {
            let asset = fetchResult.object(at: index)
            let preferredFilename = Self.preferredResource(for: asset)?.originalFilename
            descriptors.append(
                TransferAssetDescriptor(
                    assetID: asset.localIdentifier,
                    assetVersion: Self.assetVersion(for: asset),
                    filename: preferredFilename ?? Self.fallbackFilename(for: asset),
                    mediaType: Self.mediaType(for: asset),
                    createdAt: asset.creationDate,
                    updatedAt: asset.modificationDate ?? asset.creationDate
                )
            )
        }

        let nextCursor: Int? = endIndex < totalCount ? endIndex : nil
        return TransferAssetBatch(
            descriptors: descriptors,
            nextCursor: nextCursor,
            totalCount: totalCount
        )
    }

    private func fetchResultForTransfer(refresh: Bool) async throws -> PHFetchResult<PHAsset>? {
        if !refresh, let cachedFetchResult {
            return cachedFetchResult
        }
        let authorizationStatus = await requestAuthorizationIfNeeded()
        TransferDebugLogger.info("Photo library authorization status=\(authorizationStatus.transferDescription)")
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            TransferDebugLogger.warning("Photo library access is unavailable for transfer.")
            return nil
        }

        let fetchResult = PHAsset.fetchAssets(with: nil)
        cachedFetchResult = fetchResult
        TransferDebugLogger.info(
            "Prepared transferable asset cursor total_count=\(fetchResult.count)"
        )
        return fetchResult
    }

    func releaseTransferRunResources() async {
        cachedFetchResult = nil
    }

    func exportAsset(_ descriptor: TransferAssetDescriptor) async throws -> ExportedTransferAsset {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [descriptor.assetID], options: nil)
        guard let asset = fetchResult.firstObject
        else {
            TransferDebugLogger.error(
                "Photo library asset is unavailable for export \(TransferDebugLogger.assetSummary(for: descriptor))"
            )
            throw TransferClientError.transport(message: "The selected photo library asset is no longer available.")
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = Self.preferredResource(from: resources) else {
            TransferDebugLogger.error(
                "Photo library asset has no exportable resource \(TransferDebugLogger.assetSummary(for: descriptor))"
            )
            throw TransferClientError.transport(message: "The selected photo library asset is missing export data.")
        }

        let hasAdjustmentData = resources.contains(where: { $0.type == .adjustmentData })
        let sourceFilename = Self.preferredOriginalFilename(
            from: resources,
            fallback: descriptor.filename
        )
        let exportStart = ProcessInfo.processInfo.systemUptime
        let exportMemoryBefore = ProcessMemorySnapshot.capture()
        let preparedExport: PreparedExportFile
        let exportStrategy: String
        do {
            if asset.mediaType == .image, hasAdjustmentData {
                exportStrategy = "current_image"
                TransferDebugLogger.debug(
                    "Exporting edited image via current-render pipeline \(TransferDebugLogger.assetSummary(for: descriptor))"
                )
                preparedExport = try await Self.exportCurrentImage(
                    asset: asset,
                    descriptor: descriptor,
                    sourceFilename: sourceFilename,
                    renderedFilename: resource.originalFilename
                )
            } else if asset.mediaType == .video, hasAdjustmentData {
                exportStrategy = "current_video"
                TransferDebugLogger.debug(
                    "Exporting edited video via AVAssetExportSession \(TransferDebugLogger.assetSummary(for: descriptor))"
                )
                preparedExport = try await Self.exportCurrentVideo(
                    asset: asset,
                    descriptor: descriptor,
                    sourceFilename: sourceFilename,
                    renderedFilename: resource.originalFilename
                )
            } else {
                exportStrategy = "resource_stream"
                if asset.mediaType == .image {
                    TransferDebugLogger.debug(
                        "Exporting unedited image via resource stream \(TransferDebugLogger.assetSummary(for: descriptor))"
                    )
                }
                preparedExport = try await Self.exportResource(
                    resource: resource,
                    descriptor: descriptor
                )
            }
        } catch {
            let exportDurationSeconds = ProcessInfo.processInfo.systemUptime - exportStart
            logExportMemorySpikeIfNeeded(
                descriptor: descriptor,
                memoryBefore: exportMemoryBefore,
                memoryAfter: ProcessMemorySnapshot.capture(),
                exportDurationSeconds: exportDurationSeconds,
                didSucceed: false,
                context: "asset_export:failed"
            )
            throw error
        }
        let exportDurationSeconds = ProcessInfo.processInfo.systemUptime - exportStart
        logExportMemorySpikeIfNeeded(
            descriptor: descriptor,
            memoryBefore: exportMemoryBefore,
            memoryAfter: ProcessMemorySnapshot.capture(),
            exportDurationSeconds: exportDurationSeconds,
            didSucceed: true,
            context: "asset_export:\(exportStrategy)"
        )

        let fileSize = (try? preparedExport.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let contentSHA1: String
        do {
            contentSHA1 = try Self.sha1Hex(for: preparedExport.fileURL)
        } catch {
            TransferDebugLogger.error(
                "Failed to hash exported asset \(TransferDebugLogger.assetSummary(for: descriptor)) error=\(TransferDebugLogger.describe(error))"
            )
            throw TransferClientError.transport(message: "The exported asset could not be hashed for transfer verification.")
        }
        TransferDebugLogger.debug(
            "Exported asset \(TransferDebugLogger.assetSummary(for: descriptor)) exported_filename=\(preparedExport.filename) bytes=\(fileSize) sha1=\(contentSHA1)"
        )

        var exportedDescriptor = descriptor
        exportedDescriptor.filename = preparedExport.filename
        return ExportedTransferAsset(
            descriptor: exportedDescriptor,
            fileURL: preparedExport.fileURL,
            mimeType: preparedExport.mimeType,
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
        preferredResource(from: PHAssetResource.assetResources(for: asset))
    }

    private static func preferredResource(from resources: [PHAssetResource]) -> PHAssetResource? {
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

    private static func exportResource(
        resource: PHAssetResource,
        descriptor: TransferAssetDescriptor
    ) async throws -> PreparedExportFile {
        let exportURL = temporaryExportURL(pathExtension: (descriptor.filename as NSString).pathExtension)
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
        return PreparedExportFile(
            fileURL: exportURL,
            mimeType: UTType(resource.uniformTypeIdentifier)?.preferredMIMEType,
            filename: descriptor.filename
        )
    }

    private static func exportCurrentImage(
        asset: PHAsset,
        descriptor: TransferAssetDescriptor,
        sourceFilename: String,
        renderedFilename: String
    ) async throws -> PreparedExportFile {
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.version = .current
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<PreparedExportFile, Error>) in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: requestOptions) {
                data, dataUTI, _, info in
                if let error = info?[PHImageErrorKey] as? NSError {
                    continuation.resume(throwing: error)
                    return
                }
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "Photo library image export was cancelled."
                        )
                    )
                    return
                }
                if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud, data == nil {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "The selected image is stored in iCloud and could not be downloaded for transfer."
                        )
                    )
                    return
                }
                guard let data else {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "The selected image could not be exported from the photo library."
                        )
                    )
                    return
                }
                do {
                    let renderedType = dataUTI.flatMap(UTType.init)
                    let outputExtension = renderedType?.preferredFilenameExtension ?? (descriptor.filename as NSString).pathExtension
                    let exportURL = temporaryExportURL(pathExtension: outputExtension)
                    try autoreleasepool {
                        try data.write(to: exportURL)
                    }
                    let exportedFilename = editedExportFilename(
                        sourceFilename: sourceFilename,
                        renderedFilename: renderedFilename,
                        pathExtension: outputExtension
                    )
                    TransferDebugLogger.debug(
                        "Exported image with current edits \(TransferDebugLogger.assetSummary(for: descriptor)) source_filename=\(sourceFilename) rendered_filename=\(renderedFilename) data_uti=\(dataUTI ?? "-")"
                    )
                    continuation.resume(
                        returning: PreparedExportFile(
                            fileURL: exportURL,
                            mimeType: renderedType?.preferredMIMEType,
                            filename: exportedFilename
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func exportCurrentVideo(
        asset: PHAsset,
        descriptor: TransferAssetDescriptor,
        sourceFilename: String,
        renderedFilename: String
    ) async throws -> PreparedExportFile {
        let requestOptions = PHVideoRequestOptions()
        requestOptions.version = .current
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        let exportOutput = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(URL, String), Error>) in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: requestOptions) {
                avAsset, audioMix, info in
                if let error = info?[PHImageErrorKey] as? NSError {
                    continuation.resume(throwing: error)
                    return
                }
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "Photo library video export was cancelled."
                        )
                    )
                    return
                }
                if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud, avAsset == nil {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "The selected video is stored in iCloud and could not be downloaded for transfer."
                        )
                    )
                    return
                }
                guard let avAsset else {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "The selected video could not be exported from the photo library."
                        )
                    )
                    return
                }
                guard let exportSession = AVAssetExportSession(
                    asset: avAsset,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "The selected edited video could not start a high-quality export session."
                        )
                    )
                    return
                }
                guard let outputFileType = supportedVideoOutputFileType(
                    from: exportSession.supportedFileTypes,
                    preferredFilename: descriptor.filename
                ) else {
                    continuation.resume(
                        throwing: TransferClientError.transport(
                            message: "The selected edited video could not find a supported export format."
                        )
                    )
                    return
                }
                let outputExtension = videoFilenameExtension(for: outputFileType) ?? (descriptor.filename as NSString).pathExtension
                let exportURL = temporaryExportURL(pathExtension: outputExtension)
                exportSession.outputURL = exportURL
                exportSession.outputFileType = outputFileType
                exportSession.audioMix = audioMix
                let exportSessionBox = ExportSessionBox(exportSession)
                exportSessionBox.session.exportAsynchronously {
                    let completedSession = exportSessionBox.session
                    switch completedSession.status {
                    case .completed:
                        continuation.resume(returning: (exportURL, outputFileType.rawValue))
                    case .failed:
                        continuation.resume(
                            throwing: completedSession.error ?? TransferClientError.transport(
                                message: "The selected edited video failed to export."
                            )
                        )
                    case .cancelled:
                        continuation.resume(
                            throwing: TransferClientError.transport(
                                message: "Photo library video export was cancelled."
                            )
                        )
                    default:
                        continuation.resume(
                            throwing: TransferClientError.transport(
                                message: "The selected edited video did not finish exporting."
                            )
                        )
                    }
                }
            }
        }
        let outputFileType = AVFileType(rawValue: exportOutput.1)
        let outputExtension = videoFilenameExtension(for: outputFileType) ?? (descriptor.filename as NSString).pathExtension
        let exportedFilename = editedExportFilename(
            sourceFilename: sourceFilename,
            renderedFilename: renderedFilename,
            pathExtension: outputExtension
        )
        TransferDebugLogger.debug(
            "Exported edited video composition \(TransferDebugLogger.assetSummary(for: descriptor)) source_filename=\(sourceFilename) rendered_filename=\(renderedFilename) output_type=\(exportOutput.1)"
        )
        return PreparedExportFile(
            fileURL: exportOutput.0,
            mimeType: mimeType(for: outputFileType),
            filename: exportedFilename
        )
    }

    private static func temporaryExportURL(pathExtension: String) -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased())
        let cleanedExtension = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedExtension.isEmpty else {
            return baseURL
        }
        return baseURL.appendingPathExtension(cleanedExtension)
    }

    private static func supportedVideoOutputFileType(
        from supportedFileTypes: [AVFileType],
        preferredFilename: String
    ) -> AVFileType? {
        let preferredExtension = (preferredFilename as NSString).pathExtension.lowercased()
        let preferredType: AVFileType? = switch preferredExtension {
        case "mp4":
            .mp4
        case "m4v":
            .m4v
        case "mov":
            .mov
        default:
            nil
        }
        if let preferredType, supportedFileTypes.contains(preferredType) {
            return preferredType
        }
        for fallbackType in [AVFileType.mp4, AVFileType.mov, AVFileType.m4v] where supportedFileTypes.contains(fallbackType) {
            return fallbackType
        }
        return supportedFileTypes.first
    }

    private static func videoFilenameExtension(for fileType: AVFileType) -> String? {
        switch fileType {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        case .m4v:
            return "m4v"
        default:
            return UTType(fileType.rawValue)?.preferredFilenameExtension
        }
    }

    private static func mimeType(for fileType: AVFileType) -> String? {
        if let preferred = UTType(fileType.rawValue)?.preferredMIMEType {
            return preferred
        }
        switch fileType {
        case .mp4, .m4v:
            return "video/mp4"
        case .mov:
            return "video/quicktime"
        default:
            return nil
        }
    }

    private static func filename(for sourceFilename: String, pathExtension: String) -> String {
        let cleanedExtension = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedExtension.isEmpty else {
            return sourceFilename
        }
        let normalizedStem = filenameStem(for: sourceFilename)
        return "\(normalizedStem).\(cleanedExtension)"
    }

    private static func editedExportFilename(
        sourceFilename: String,
        renderedFilename: String,
        pathExtension: String
    ) -> String {
        let cleanedExtension = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedExtension.isEmpty else {
            return sourceFilename
        }
        let sourceStem = filenameStem(for: sourceFilename)
        let renderedStem = filenameStem(for: renderedFilename)
        guard !sourceStem.isEmpty else {
            guard !renderedStem.isEmpty else {
                return sourceFilename
            }
            return "\(renderedStem).\(cleanedExtension)"
        }
        guard !renderedStem.isEmpty, renderedStem.caseInsensitiveCompare(sourceStem) != .orderedSame else {
            return "\(sourceStem).\(cleanedExtension)"
        }
        return "\(sourceStem).\(renderedStem).\(cleanedExtension)"
    }

    private static func preferredOriginalFilename(from resources: [PHAssetResource], fallback: String) -> String {
        let preferredTypes: [PHAssetResourceType] = [
            .photo,
            .video,
            .fullSizePhoto,
            .fullSizeVideo,
        ]
        for resourceType in preferredTypes {
            if let resource = resources.first(where: {
                $0.type == resourceType && !isGenericRenderFilename($0.originalFilename)
            }) {
                return resource.originalFilename
            }
        }
        for resourceType in preferredTypes {
            if let resource = resources.first(where: { $0.type == resourceType }) {
                return resource.originalFilename
            }
        }
        return fallback
    }

    private static func isGenericRenderFilename(_ filename: String) -> Bool {
        let stem = filenameStem(for: filename).lowercased()
        return stem == "fullsizerender" || stem == "renderedvideo"
    }

    private static func filenameStem(for filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        return stem.isEmpty ? filename : stem
    }

    private static func sha1Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = Insecure.SHA1()
        while true {
            let hasChunk = try autoreleasepool { () throws -> Bool in
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                guard !chunk.isEmpty else {
                    return false
                }
                hasher.update(data: chunk)
                return true
            }
            if !hasChunk {
                break
            }
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

    private static func fallbackFilename(for asset: PHAsset) -> String {
        let normalizedIdentifier = asset.localIdentifier
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fallbackExtension = asset.mediaType == .video ? "mov" : "jpg"
        return "\(normalizedIdentifier).\(fallbackExtension)"
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

private struct PreparedTransferUploadResult: Sendable {
    let preparedAsset: PreparedTransferAsset
    let existingMatch: TransferAssetExistenceMatch?
    let response: TransferServerResponse?
    let errorDescription: String?
    let terminalFailureCode: TransferFailureCode?
    let terminalFailureMessage: String?
    let existenceCheckDurationSeconds: Double
    let uploadDurationSeconds: Double
}

private struct ExportPipelineResult: Sendable {
    let descriptor: TransferAssetDescriptor
    let preparedAsset: PreparedTransferAsset?
    let errorDescription: String?
    let exportDurationSeconds: Double
}

private struct TransferStageMetrics {
    var exportDurations: [Double] = []
    var existenceCheckDurations: [Double] = []
    var uploadDurations: [Double] = []
}

private struct StageDurationSummary {
    let count: Int
    let averageMilliseconds: Double
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let totalSeconds: Double
}

private struct ProcessMemorySnapshot {
    let physicalFootprintBytes: UInt64
    let residentSizeBytes: UInt64

    static func capture() -> ProcessMemorySnapshot? {
        var info = task_vm_info_data_t()
        var infoCount = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { integerPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    integerPointer,
                    &infoCount
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return ProcessMemorySnapshot(
            physicalFootprintBytes: info.phys_footprint,
            residentSizeBytes: info.resident_size
        )
    }
}

private actor PreparedTransferAssetQueue {
    private var bufferedItems: [ExportPipelineResult] = []
    private var pendingConsumers: [CheckedContinuation<ExportPipelineResult?, Never>] = []
    private var isFinished = false

    func enqueue(_ item: ExportPipelineResult) {
        if let pendingConsumer = pendingConsumers.first {
            pendingConsumers.removeFirst()
            pendingConsumer.resume(returning: item)
            return
        }
        bufferedItems.append(item)
    }

    func dequeue() async -> ExportPipelineResult? {
        if !bufferedItems.isEmpty {
            return bufferedItems.removeFirst()
        }
        if isFinished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            pendingConsumers.append(continuation)
        }
    }

    func tryDequeue() -> ExportPipelineResult? {
        guard !bufferedItems.isEmpty else {
            return nil
        }
        return bufferedItems.removeFirst()
    }

    func finish() {
        isFinished = true
        let consumers = pendingConsumers
        pendingConsumers.removeAll(keepingCapacity: false)
        for consumer in consumers {
            consumer.resume(returning: nil)
        }
    }
}

private func lookupExistingAssets(
    transferClient: MobileTransferClient,
    candidates: [TransferAssetExistenceCandidate],
    desktop: TrustedDesktopRecord,
    preferredTransport: TransferTransport?
) async throws -> [String: TransferAssetExistenceMatch] {
    if let preferredTransportClient = transferClient as? any PreferredTransportMobileTransferClient {
        return try await preferredTransportClient.lookupExistingAssets(
            candidates,
            desktop: desktop,
            preferredTransport: preferredTransport
        )
    }
    return try await transferClient.lookupExistingAssets(candidates, desktop: desktop)
}

private func uploadPreparedAsset(
    transferClient: MobileTransferClient,
    asset: ExportedTransferAsset,
    desktop: TrustedDesktopRecord,
    preferredTransport: TransferTransport?,
    onChunkTransferred: (@Sendable (Int) async -> Void)? = nil
) async throws -> TransferServerResponse {
    if let chunkPreferredTransportClient = transferClient as? any ChunkProgressPreferredTransportMobileTransferClient,
       let onChunkTransferred
    {
        return try await chunkPreferredTransportClient.uploadAsset(
            asset,
            desktop: desktop,
            preferredTransport: preferredTransport,
            onChunkTransferred: onChunkTransferred
        )
    }
    if let preferredTransportClient = transferClient as? any PreferredTransportMobileTransferClient {
        return try await preferredTransportClient.uploadAsset(
            asset,
            desktop: desktop,
            preferredTransport: preferredTransport
        )
    }
    if let chunkTransferClient = transferClient as? any ChunkProgressMobileTransferClient,
       let onChunkTransferred
    {
        return try await chunkTransferClient.uploadAsset(
            asset,
            desktop: desktop,
            onChunkTransferred: onChunkTransferred
        )
    }
    return try await transferClient.uploadAsset(asset, desktop: desktop)
}

private func performPreparedAssetUpload(
    preparedAsset: PreparedTransferAsset,
    desktop: TrustedDesktopRecord,
    transferClient: MobileTransferClient,
    telemetryClient: TelemetryClient,
    preferredTransport: TransferTransport?,
    onChunkTransferred: (@Sendable (Int) async -> Void)? = nil
) async -> PreparedTransferUploadResult {
    var existenceCheckDurationSeconds = 0.0
    var uploadDurationSeconds = 0.0
    do {
        try Task.checkCancellation()
        if let existenceCandidate = preparedAsset.existenceCandidate {
            let existenceStart = ProcessInfo.processInfo.systemUptime
            let matches = try await lookupExistingAssets(
                transferClient: transferClient,
                candidates: [existenceCandidate],
                desktop: desktop,
                preferredTransport: preferredTransport
            )
            existenceCheckDurationSeconds = ProcessInfo.processInfo.systemUptime - existenceStart
            if let existingMatch = matches[preparedAsset.exportedAsset.descriptor.assetID] {
                return PreparedTransferUploadResult(
                    preparedAsset: preparedAsset,
                    existingMatch: existingMatch,
                    response: nil,
                    errorDescription: nil,
                    terminalFailureCode: nil,
                    terminalFailureMessage: nil,
                    existenceCheckDurationSeconds: existenceCheckDurationSeconds,
                    uploadDurationSeconds: uploadDurationSeconds
                )
            }
        }
        try Task.checkCancellation()
        let uploadStart = ProcessInfo.processInfo.systemUptime
        let response = try await telemetryClient.withSpan(
            name: "mobile.backup.asset.upload",
            attributes: assetPipelineTelemetryAttributes(
                descriptor: preparedAsset.exportedAsset.descriptor,
                sessionID: desktop.lastSessionID,
                stage: "upload",
                preferredTransport: preferredTransport,
                fileSizeBytes: preparedAsset.exportedAsset.fileSize
            )
        ) {
            try await uploadPreparedAsset(
                transferClient: transferClient,
                asset: preparedAsset.exportedAsset,
                desktop: desktop,
                preferredTransport: preferredTransport,
                onChunkTransferred: onChunkTransferred
            )
        }
        uploadDurationSeconds = ProcessInfo.processInfo.systemUptime - uploadStart
        return PreparedTransferUploadResult(
            preparedAsset: preparedAsset,
            existingMatch: nil,
            response: response,
            errorDescription: nil,
            terminalFailureCode: nil,
            terminalFailureMessage: nil,
            existenceCheckDurationSeconds: existenceCheckDurationSeconds,
            uploadDurationSeconds: uploadDurationSeconds
        )
    } catch let error as TransferClientError {
        return PreparedTransferUploadResult(
            preparedAsset: preparedAsset,
            existingMatch: nil,
            response: nil,
            errorDescription: TransferDebugLogger.describe(error),
            terminalFailureCode: error.terminalFailureCode,
            terminalFailureMessage: error.message,
            existenceCheckDurationSeconds: existenceCheckDurationSeconds,
            uploadDurationSeconds: uploadDurationSeconds
        )
    } catch {
        return PreparedTransferUploadResult(
            preparedAsset: preparedAsset,
            existingMatch: nil,
            response: nil,
            errorDescription: TransferDebugLogger.describe(error),
            terminalFailureCode: nil,
            terminalFailureMessage: nil,
            existenceCheckDurationSeconds: existenceCheckDurationSeconds,
            uploadDurationSeconds: uploadDurationSeconds
        )
    }
}

private func exportPipelineResult(
    descriptor: TransferAssetDescriptor,
    exportSource: TransferAssetSource,
    sessionID: String,
    telemetryClient: TelemetryClient
) async -> ExportPipelineResult {
    let exportStart = ProcessInfo.processInfo.systemUptime
    let memoryBefore = ProcessMemorySnapshot.capture()
    do {
        try Task.checkCancellation()
        let exportedAsset = try await telemetryClient.withSpan(
            name: "mobile.backup.asset.export",
            attributes: assetPipelineTelemetryAttributes(
                descriptor: descriptor,
                sessionID: sessionID,
                stage: "export"
            )
        ) {
            try await exportSource.exportAsset(descriptor)
        }
        if Task.isCancelled {
            try? FileManager.default.removeItem(at: exportedAsset.fileURL)
            throw CancellationError()
        }
        let exportDurationSeconds = ProcessInfo.processInfo.systemUptime - exportStart
        logExportMemorySpikeIfNeeded(
            descriptor: descriptor,
            memoryBefore: memoryBefore,
            memoryAfter: ProcessMemorySnapshot.capture(),
            exportDurationSeconds: exportDurationSeconds,
            didSucceed: true,
            context: "pipeline_result"
        )
        return ExportPipelineResult(
            descriptor: descriptor,
            preparedAsset: PreparedTransferAsset(exportedAsset: exportedAsset),
            errorDescription: nil,
            exportDurationSeconds: exportDurationSeconds
        )
    } catch {
        let exportDurationSeconds = ProcessInfo.processInfo.systemUptime - exportStart
        logExportMemorySpikeIfNeeded(
            descriptor: descriptor,
            memoryBefore: memoryBefore,
            memoryAfter: ProcessMemorySnapshot.capture(),
            exportDurationSeconds: exportDurationSeconds,
            didSucceed: false,
            context: "pipeline_result"
        )
        return ExportPipelineResult(
            descriptor: descriptor,
            preparedAsset: nil,
            errorDescription: TransferDebugLogger.describe(error),
            exportDurationSeconds: exportDurationSeconds
        )
    }
}

private func assetPipelineTelemetryAttributes(
    descriptor: TransferAssetDescriptor,
    sessionID: String,
    stage: String,
    preferredTransport: TransferTransport? = nil,
    fileSizeBytes: Int? = nil
) -> MobileTelemetryAttributes {
    var attributes: MobileTelemetryAttributes = [
        "correlation.session_id": .string(sessionID),
        "transfer.asset_id": .string(descriptor.assetID),
        "transfer.asset_version": .string(descriptor.assetVersion),
        "transfer.asset_filename": .string(descriptor.filename),
        "transfer.asset_media_type": .string(descriptor.mediaType),
        "transfer.pipeline_stage": .string(stage),
    ]
    if let preferredTransport {
        attributes["transfer.transport"] = .string(preferredTransport.rawValue)
    }
    if let fileSizeBytes {
        attributes["transfer.asset_file_size_bytes"] = .int(fileSizeBytes)
    }
    return attributes
}

private let exportMemorySpikeThresholdBytes: Int64 = 256 * 1024 * 1024

private func logExportMemorySpikeIfNeeded(
    descriptor: TransferAssetDescriptor,
    memoryBefore: ProcessMemorySnapshot?,
    memoryAfter: ProcessMemorySnapshot?,
    exportDurationSeconds: Double,
    didSucceed: Bool,
    context: String
) {
    guard let memoryBefore, let memoryAfter else {
        return
    }
    let footprintDeltaBytes = Int64(memoryAfter.physicalFootprintBytes) - Int64(memoryBefore.physicalFootprintBytes)
    guard footprintDeltaBytes >= exportMemorySpikeThresholdBytes else {
        return
    }
    let footprintDeltaMB = Double(footprintDeltaBytes) / 1_048_576
    let footprintAfterMB = Double(memoryAfter.physicalFootprintBytes) / 1_048_576
    let residentAfterMB = Double(memoryAfter.residentSizeBytes) / 1_048_576
    TransferDebugLogger.warning(
        String(
            format: "Transfer export memory spike context=%@ asset=%@ status=%@ delta=%.1fMB footprint=%.1fMB resident=%.1fMB duration=%.2fs",
            context,
            TransferDebugLogger.assetSummary(for: descriptor),
            didSucceed ? "succeeded" : "failed",
            footprintDeltaMB,
            footprintAfterMB,
            residentAfterMB,
            exportDurationSeconds
        )
    )
}

actor PhotoLibraryTransferService: TransferService {
    private struct TransferSpeedSample {
        let timestamp: Date
        let bytes: Int
    }

    private struct UploadLane {
        let preferredTransport: TransferTransport?
        let concurrencyLimit: Int
    }

    private static let transferSpeedWindowSeconds: TimeInterval = 10
    private static let assetFetchBatchSize = 100
    private static let lanUploadConcurrencyMax = 3
    private static let usbUploadConcurrencyMax = 2
    private let assetSource: TransferAssetSource
    private let transferClient: MobileTransferClient
    private let transportResolver: (any TransferTransportResolving)?
    private let liveTransportResolver: (any TransferLiveTransportResolving)?
    private let trustedDesktopStore: TrustedDesktopStore
    private let telemetryClient: TelemetryClient
    private let exportConcurrencyLimit: Int
    private let uploadConcurrencyLimit: Int
    private var transferSpeedSamples: [TransferSpeedSample] = []
    private var transferRunStartedAtUptimeSeconds: TimeInterval?
    private var totalPreparedTransferBytes = 0
    private var processedPreparedTransferBytes = 0
    private var nonSkippedTransferredBytesForSpeed = 0
    private var successfullyTransferredAssetIDs: Set<String> = []
    private var stopRequested = false
    private var currentSnapshot: TransferSnapshot?
    private var currentCompletionState: TransferCompletionState?

    init(
        assetSource: TransferAssetSource,
        transferClient: MobileTransferClient,
        trustedDesktopStore: TrustedDesktopStore,
        telemetryClient: TelemetryClient = NoOpTelemetryClient(),
        exportConcurrencyLimit: Int = 5,
        uploadConcurrencyLimit: Int = 5
    ) {
        self.assetSource = assetSource
        self.transferClient = transferClient
        self.transportResolver = transferClient as? any TransferTransportResolving
        self.liveTransportResolver = transferClient as? any TransferLiveTransportResolving
        self.trustedDesktopStore = trustedDesktopStore
        self.telemetryClient = telemetryClient
        self.exportConcurrencyLimit = max(1, exportConcurrencyLimit)
        self.uploadConcurrencyLimit = max(1, uploadConcurrencyLimit)
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        await runTransfer(progress: progress)
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        stopRequested = true
        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            return .stoppedByUser
        }
        _ = await reportStoppedTransferToDesktop(
            desktop: trustedDesktop,
            transferredCount: current.transferredCount,
            failedCount: current.failedCount
        )
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
                failedCount: current.failedCount,
                interruptionReason: nil
            )
            let resolvedTransport = await resolvedTransport(for: trustedDesktop)
            var completedSnapshot = current
            completedSnapshot.transport = resolvedTransport
            completedSnapshot.statusMessage = "Desktop confirmed that this transfer session is complete."
            completedSnapshot.guidanceMessage = "You can return home and start another backup whenever new media appears on the device."
            completedSnapshot = await applyingLiveTransports(
                to: completedSnapshot,
                desktop: trustedDesktop
            )
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
            failedSnapshot = await applyingLiveTransports(
                to: failedSnapshot,
                desktop: trustedDesktop
            )
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
            failedSnapshot = await applyingLiveTransports(
                to: failedSnapshot,
                desktop: trustedDesktop
            )
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
            snapshot = await applyingLiveTransports(
                to: snapshot,
                desktop: trustedDesktop
            )
        }
        snapshot.transferSpeedText = currentTransferSpeedText()
        snapshot.etaMinutes = currentETAMinutes(
            transferredCount: snapshot.transferredCount,
            totalCount: snapshot.totalCount,
            failedCount: snapshot.failedCount
        )
        currentSnapshot = snapshot
        return snapshot
    }

    func stageTransferSnapshot(_ snapshot: TransferSnapshot) async {
        currentSnapshot = snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        currentCompletionState
    }

    func stageTransferCompletionState(_ completionState: TransferCompletionState?) async {
        currentCompletionState = completionState
        if let snapshot = completionState?.snapshot {
            currentSnapshot = snapshot
        }
    }

    func handleAppDidBecomeActive() async {
        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            return
        }
        guard let usbForegroundRecovery = transferClient as? any USBTransportForegroundRecovering else {
            return
        }
        await usbForegroundRecovery.recoverUSBTransportAfterForegroundResume(for: trustedDesktop)
    }

    func handleMemoryWarning() async {
        TransferDebugLogger.warning(
            "iOS memory warning received upload_concurrency_limit=\(uploadConcurrencyLimit)"
        )
        await assetSource.releaseTransferRunResources()
        logTransferMemoryUsage(event: "memory_warning")
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        let candidateAssetIDs = Array(successfullyTransferredAssetIDs)
        guard !candidateAssetIDs.isEmpty else {
            return .skipped
        }

        let fetchedAssets = PHAsset.fetchAssets(withLocalIdentifiers: candidateAssetIDs, options: nil)
        guard fetchedAssets.count > 0 else {
            successfullyTransferredAssetIDs.removeAll()
            return .skipped
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets(fetchedAssets)
                }) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(
                            throwing: TransferClientError.transport(
                                message: "Photo library cleanup did not complete successfully."
                            )
                        )
                    }
                }
            }
            let removedCount = fetchedAssets.count
            successfullyTransferredAssetIDs.removeAll()
            TransferDebugLogger.info(
                "Moved transferred assets to Recently Removed removed_count=\(removedCount)"
            )
            return .removed(removedCount)
        } catch {
            let message = "Photo library cleanup failed. \(error.localizedDescription)"
            TransferDebugLogger.error(
                "Failed to move transferred assets to Recently Removed error=\(TransferDebugLogger.describe(error))"
            )
            return .failed(message: message)
        }
    }

    private func runTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        stopRequested = false
        successfullyTransferredAssetIDs.removeAll()
        currentCompletionState = nil
        totalPreparedTransferBytes = 0
        processedPreparedTransferBytes = 0
        nonSkippedTransferredBytesForSpeed = 0

        guard let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop() else {
            let failedSnapshot = TransferSnapshot(
                transferredCount: 0,
                totalCount: 0,
                failedCount: 0,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "No paired desktop record is available for transfer.",
                guidanceMessage: "Pair with the desktop again before starting a backup.",
                isIncompleteLibrary: false
            )
            currentSnapshot = failedSnapshot
            return await finalizingTransferRun(failedSnapshot)
        }

        do {
            var assetBatch = try await assetSource.fetchAssetBatch(
                cursor: nil,
                batchSize: Self.assetFetchBatchSize
            )
            if assetBatch.totalCount == 0 {
                TransferDebugLogger.warning("Transfer did not start because there are no eligible local assets.")
                let resolvedTransport = await resolvedTransport(for: trustedDesktop)
                let emptySnapshot = TransferSnapshot(
                    transferredCount: 0,
                    totalCount: 0,
                    failedCount: 0,
                    transport: resolvedTransport,
                    etaMinutes: nil,
                    statusMessage: "No eligible local photo or video assets are ready for transfer.",
                    guidanceMessage: "Check photo-library access or capture new media, then retry the backup.",
                    isIncompleteLibrary: false
                )
                let snapshotWithLiveTransports = await applyingLiveTransports(
                    to: emptySnapshot,
                    desktop: trustedDesktop
                )
                currentSnapshot = snapshotWithLiveTransports
                return await finalizingTransferRun(snapshotWithLiveTransports)
            }
            let totalCount = assetBatch.totalCount
            if stopRequested {
                let pausedSnapshot = await pausedSnapshotForStoppedTransfer(
                    desktop: trustedDesktop,
                    transferredCount: 0,
                    totalCount: totalCount,
                    failedCount: 0,
                    skippedCount: 0
                )
                return await finalizingTransferRun(pausedSnapshot)
            }

            TransferDebugLogger.info(
                "Starting backup run desktop=\(trustedDesktop.desktopName) session_id=\(trustedDesktop.lastSessionID) asset_count=\(totalCount) batch_size=\(Self.assetFetchBatchSize)"
            )
            try await transferClient.startSession(desktop: trustedDesktop, totalAssets: totalCount)
            if stopRequested {
                _ = await reportStoppedTransferToDesktop(
                    desktop: trustedDesktop,
                    transferredCount: 0,
                    failedCount: 0
                )
                let pausedSnapshot = await pausedSnapshotForStoppedTransfer(
                    desktop: trustedDesktop,
                    transferredCount: 0,
                    totalCount: totalCount,
                    failedCount: 0,
                    skippedCount: 0
                )
                return await finalizingTransferRun(pausedSnapshot)
            }
            resetTransferSpeedWindow()
            logTransferMemoryUsage(
                event: "transfer_start",
                processedCount: 0,
                totalCount: totalCount
            )
            let transferRunStartSeconds = ProcessInfo.processInfo.systemUptime
            transferRunStartedAtUptimeSeconds = transferRunStartSeconds

            var transferredCount = 0
            var failedCount = 0
            var skippedCount = 0
            var stageMetrics = TransferStageMetrics()
            let initialTransport = await resolvedTransport(for: trustedDesktop)
            let initialSnapshot = makeProgressSnapshot(
                transport: initialTransport,
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount,
                skippedCount: skippedCount
            )
            let initialSnapshotWithLiveTransports = await applyingLiveTransports(
                to: initialSnapshot,
                desktop: trustedDesktop
            )
            currentSnapshot = initialSnapshotWithLiveTransports
            progress(initialSnapshotWithLiveTransports)

            while true {
                if !assetBatch.descriptors.isEmpty,
                   let pausedSnapshot = await processTransferPipeline(
                       assets: assetBatch.descriptors,
                       desktop: trustedDesktop,
                       totalCount: totalCount,
                       transferredCount: &transferredCount,
                       failedCount: &failedCount,
                       skippedCount: &skippedCount,
                       stageMetrics: &stageMetrics,
                       progress: progress
                   )
                {
                    let transferRunDurationSeconds = ProcessInfo.processInfo.systemUptime - transferRunStartSeconds
                    logTransferStageMetrics(
                        desktop: trustedDesktop,
                        totalCount: totalCount,
                        transferredCount: transferredCount,
                        failedCount: failedCount,
                        runDurationSeconds: transferRunDurationSeconds,
                        stageMetrics: stageMetrics
                    )
                    return await finalizingTransferRun(pausedSnapshot)
                }

                guard let nextCursor = assetBatch.nextCursor else {
                    break
                }
                assetBatch = try await assetSource.fetchAssetBatch(
                    cursor: nextCursor,
                    batchSize: Self.assetFetchBatchSize
                )
            }

            TransferDebugLogger.info(
                "Transfer run finished session_id=\(trustedDesktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount) total=\(totalCount)"
            )
            let completedTransport = await resolvedTransport(for: trustedDesktop)
            let completedSnapshot = TransferSnapshot(
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount,
                skippedCount: skippedCount,
                transport: completedTransport,
                transferSpeedText: currentTransferSpeedText(),
                etaMinutes: nil,
                statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
                guidanceMessage: failedCount == 0
                    ? "Backup completes automatically after the desktop confirms this transfer session."
                    : "Some items could not be transferred. Start another backup session to retry remaining items, then inspect the MobileTransfer device logs for per-item errors.",
                isIncompleteLibrary: false
            )
            let completedSnapshotWithLiveTransports = await applyingLiveTransports(
                to: completedSnapshot,
                desktop: trustedDesktop
            )
            let transferRunDurationSeconds = ProcessInfo.processInfo.systemUptime - transferRunStartSeconds
            logTransferStageMetrics(
                desktop: trustedDesktop,
                totalCount: totalCount,
                transferredCount: transferredCount,
                failedCount: failedCount,
                runDurationSeconds: transferRunDurationSeconds,
                stageMetrics: stageMetrics
            )
            currentSnapshot = completedSnapshotWithLiveTransports
            return await finalizingTransferRun(completedSnapshotWithLiveTransports)
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
                etaMinutes: nil,
                statusMessage: error.message,
                guidanceMessage: "Retry the backup after confirming the paired desktop is reachable on the same local network.",
                isIncompleteLibrary: false
            )
            let failedSnapshotWithLiveTransports = await applyingLiveTransports(
                to: failedSnapshot,
                desktop: trustedDesktop
            )
            currentSnapshot = failedSnapshotWithLiveTransports
            return await finalizingTransferRun(failedSnapshotWithLiveTransports)
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
                etaMinutes: nil,
                statusMessage: error.localizedDescription,
                guidanceMessage: "Retry the backup after confirming photo-library access and desktop reachability.",
                isIncompleteLibrary: false
            )
            let failedSnapshotWithLiveTransports = await applyingLiveTransports(
                to: failedSnapshot,
                desktop: trustedDesktop
            )
            currentSnapshot = failedSnapshotWithLiveTransports
            return await finalizingTransferRun(failedSnapshotWithLiveTransports)
        }
    }

    private func finalizingTransferRun(_ snapshot: TransferSnapshot) async -> TransferSnapshot {
        await assetSource.releaseTransferRunResources()
        transferRunStartedAtUptimeSeconds = nil
        totalPreparedTransferBytes = 0
        processedPreparedTransferBytes = 0
        nonSkippedTransferredBytesForSpeed = 0
        return snapshot
    }

    @discardableResult
    private func reportStoppedTransferToDesktop(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        failedCount: Int
    ) async -> Bool {
        do {
            _ = try await transferClient.completeSession(
                desktop: desktop,
                transferredCount: transferredCount,
                failedCount: failedCount,
                interruptionReason: "stopped_by_user"
            )
            TransferDebugLogger.info(
                "Reported stopped transfer to desktop session_id=\(desktop.lastSessionID) transferred=\(transferredCount) failed=\(failedCount)"
            )
            return true
        } catch {
            TransferDebugLogger.warning(
                "Failed to report stopped transfer to desktop session_id=\(desktop.lastSessionID) error=\(TransferDebugLogger.describe(error))"
            )
            return false
        }
    }

    private func pausedSnapshotForStoppedTransfer(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        skippedCount: Int
    ) async -> TransferSnapshot {
        let currentTransport = await resolvedTransport(for: desktop)
        let pausedSnapshot = makePausedSnapshot(
            transport: currentTransport,
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            sessionID: desktop.lastSessionID
        )
        let pausedSnapshotWithLiveTransports = await applyingLiveTransports(
            to: pausedSnapshot,
            desktop: desktop
        )
        currentSnapshot = pausedSnapshotWithLiveTransports
        return pausedSnapshotWithLiveTransports
    }

    private func processTransferPipeline(
        assets: [TransferAssetDescriptor],
        desktop: TrustedDesktopRecord,
        totalCount: Int,
        transferredCount: inout Int,
        failedCount: inout Int,
        skippedCount: inout Int,
        stageMetrics: inout TransferStageMetrics,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async -> TransferSnapshot? {
        let preparedAssetQueue = PreparedTransferAssetQueue()
        let producerTask = Task {
            await producePreparedAssets(
                assets: assets,
                queue: preparedAssetQueue,
                sessionID: desktop.lastSessionID
            )
        }
        let uploadLanes = await configuredUploadLanes(for: desktop)

        var bufferedUploads: [PreparedTransferAsset] = []
        var producerFinished = false
        var inFlightUploadCount = 0
        var inFlightUploadCountByLane: [Int: Int] = [:]
        var nextUploadLaneIndex = 0
        var stopHandled = false
        var terminalFailureSnapshot: TransferSnapshot? = nil
        let uploadClient = transferClient
        let telemetryClient = self.telemetryClient

        await withTaskGroup(of: (Int, PreparedTransferUploadResult).self) { uploadGroup in
            while true {
                if stopRequested, !stopHandled {
                    stopHandled = true
                    producerTask.cancel()
                    uploadGroup.cancelAll()
                    cleanupPreparedAssets(bufferedUploads)
                    bufferedUploads.removeAll(keepingCapacity: false)
                }

                while let exportResult = await preparedAssetQueue.tryDequeue() {
                    stageMetrics.exportDurations.append(exportResult.exportDurationSeconds)
                    if stopHandled {
                        if let preparedAsset = exportResult.preparedAsset {
                            cleanupExportedAsset(preparedAsset.exportedAsset)
                        }
                        continue
                    }
                    if let preparedAsset = exportResult.preparedAsset {
                        totalPreparedTransferBytes += max(preparedAsset.exportedAsset.fileSize, 0)
                        bufferedUploads.append(preparedAsset)
                        continue
                    }
                    failedCount += 1
                    let assetSummary = TransferDebugLogger.assetSummary(for: exportResult.descriptor)
                    let errorDescription = exportResult.errorDescription ?? "unknown export error"
                    TransferDebugLogger.error("Transfer failed for \(assetSummary) error=\(errorDescription)")
                    await recordProgressUpdate(
                        desktop: desktop,
                        transferredCount: transferredCount,
                        totalCount: totalCount,
                        failedCount: failedCount,
                        skippedCount: skippedCount,
                        progress: progress
                    )
                }

                if !stopHandled {
                    while !bufferedUploads.isEmpty {
                        guard
                            let laneIndex = nextAvailableUploadLaneIndex(
                                lanes: uploadLanes,
                                inFlightCounts: inFlightUploadCountByLane,
                                laneCursor: &nextUploadLaneIndex
                            )
                        else {
                            break
                        }
                        let lane = uploadLanes[laneIndex]
                        let preparedAsset = bufferedUploads.removeFirst()
                        inFlightUploadCount += 1
                        inFlightUploadCountByLane[laneIndex, default: 0] += 1
                        uploadGroup.addTask {
                            (
                                laneIndex,
                                await performPreparedAssetUpload(
                                    preparedAsset: preparedAsset,
                                    desktop: desktop,
                                    transferClient: uploadClient,
                                    telemetryClient: telemetryClient,
                                    preferredTransport: lane.preferredTransport,
                                    onChunkTransferred: { [self] bytes in
                                        await recordChunkTransferProgress(
                                            bytes: bytes,
                                            progress: progress
                                        )
                                    }
                                )
                            )
                        }
                    }
                }

                if inFlightUploadCount > 0 {
                    if let (laneIndex, uploadResult) = await uploadGroup.next() {
                        inFlightUploadCount -= 1
                        if let currentLaneCount = inFlightUploadCountByLane[laneIndex] {
                            if currentLaneCount <= 1 {
                                inFlightUploadCountByLane.removeValue(forKey: laneIndex)
                            } else {
                                inFlightUploadCountByLane[laneIndex] = currentLaneCount - 1
                            }
                        }
                        if stopHandled {
                            cleanupExportedAsset(uploadResult.preparedAsset.exportedAsset)
                            continue
                        }
                        if let terminalSnapshot = await processUploadResult(
                            uploadResult,
                            desktop: desktop,
                            totalCount: totalCount,
                            transferredCount: &transferredCount,
                            failedCount: &failedCount,
                            skippedCount: &skippedCount,
                            stageMetrics: &stageMetrics,
                            progress: progress
                        ) {
                            terminalFailureSnapshot = terminalSnapshot
                            progress(terminalSnapshot)
                            stopRequested = true
                            stopHandled = true
                            producerTask.cancel()
                            uploadGroup.cancelAll()
                            cleanupPreparedAssets(bufferedUploads)
                            bufferedUploads.removeAll(keepingCapacity: false)
                        }
                        continue
                    }
                    inFlightUploadCount = 0
                    inFlightUploadCountByLane.removeAll(keepingCapacity: false)
                }

                if producerFinished {
                    break
                }

                if let exportResult = await preparedAssetQueue.dequeue() {
                    stageMetrics.exportDurations.append(exportResult.exportDurationSeconds)
                    if stopHandled {
                        if let preparedAsset = exportResult.preparedAsset {
                            cleanupExportedAsset(preparedAsset.exportedAsset)
                        }
                        continue
                    }
                    if let preparedAsset = exportResult.preparedAsset {
                        totalPreparedTransferBytes += max(preparedAsset.exportedAsset.fileSize, 0)
                        bufferedUploads.append(preparedAsset)
                    } else {
                        failedCount += 1
                        let assetSummary = TransferDebugLogger.assetSummary(for: exportResult.descriptor)
                        let errorDescription = exportResult.errorDescription ?? "unknown export error"
                        TransferDebugLogger.error("Transfer failed for \(assetSummary) error=\(errorDescription)")
                        await recordProgressUpdate(
                            desktop: desktop,
                            transferredCount: transferredCount,
                            totalCount: totalCount,
                            failedCount: failedCount,
                            skippedCount: skippedCount,
                            progress: progress
                        )
                    }
                } else {
                    producerFinished = true
                }

                if producerFinished, bufferedUploads.isEmpty, inFlightUploadCount == 0 {
                    break
                }
            }
        }

        _ = await producerTask.result

        if let terminalFailureSnapshot {
            return terminalFailureSnapshot
        }

        if stopRequested {
            return await pausedSnapshotForStoppedTransfer(
                desktop: desktop,
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount,
                skippedCount: skippedCount
            )
        }

        return nil
    }

    private func configuredUploadLanes(for desktop: TrustedDesktopRecord) async -> [UploadLane] {
        let currentTransport = await resolvedTransport(for: desktop)
        let defaultLane = [
            UploadLane(
                preferredTransport: nil,
                concurrencyLimit: cappedUploadConcurrencyLimit(for: currentTransport)
            ),
        ]
        guard uploadConcurrencyLimit >= 2 else {
            return defaultLane
        }
        guard transferClient is any PreferredTransportMobileTransferClient else {
            return defaultLane
        }
        guard currentTransport == .usb else {
            return defaultLane
        }

        let dualChannelLimits = dualChannelUploadConcurrencyLimits()
        TransferDebugLogger.info(
            "Dual-channel upload scheduling enabled "
                + "session_id=\(desktop.lastSessionID) "
                + "usb_limit=\(dualChannelLimits.usb) lan_limit=\(dualChannelLimits.lan)"
        )
        return [
            UploadLane(preferredTransport: .usb, concurrencyLimit: dualChannelLimits.usb),
            UploadLane(preferredTransport: .lan, concurrencyLimit: dualChannelLimits.lan),
        ]
    }

    private func cappedUploadConcurrencyLimit(for transport: TransferTransport) -> Int {
        let transportLimit: Int
        switch transport {
        case .lan:
            transportLimit = Self.lanUploadConcurrencyMax
        case .usb:
            transportLimit = Self.usbUploadConcurrencyMax
        }
        return max(1, min(uploadConcurrencyLimit, transportLimit))
    }

    private func dualChannelUploadConcurrencyLimits() -> (usb: Int, lan: Int) {
        let cappedTotal = max(1, uploadConcurrencyLimit)
        let usbLimit = min(Self.usbUploadConcurrencyMax, max(1, cappedTotal - 1))
        let remainingBudget = max(1, cappedTotal - usbLimit)
        let lanLimit = min(Self.lanUploadConcurrencyMax, remainingBudget)
        return (usb: usbLimit, lan: lanLimit)
    }

    private func nextAvailableUploadLaneIndex(
        lanes: [UploadLane],
        inFlightCounts: [Int: Int],
        laneCursor: inout Int
    ) -> Int? {
        guard !lanes.isEmpty else {
            return nil
        }
        let normalizedCursor = max(0, laneCursor)
        for offset in 0 ..< lanes.count {
            let candidateLaneIndex = (normalizedCursor + offset) % lanes.count
            let inFlightCount = inFlightCounts[candidateLaneIndex, default: 0]
            if inFlightCount < lanes[candidateLaneIndex].concurrencyLimit {
                laneCursor = (candidateLaneIndex + 1) % lanes.count
                return candidateLaneIndex
            }
        }
        return nil
    }

    private func producePreparedAssets(
        assets: [TransferAssetDescriptor],
        queue: PreparedTransferAssetQueue,
        sessionID: String
    ) async {
        let exportSource = assetSource
        let telemetryClient = self.telemetryClient

        await withTaskGroup(of: (Int, ExportPipelineResult).self) { group in
            var nextAssetIndex = 0
            var inFlightExportCount = 0
            var nextResultIndexToEnqueue = 0
            var pendingResultsByIndex: [Int: ExportPipelineResult] = [:]

            while inFlightExportCount < exportConcurrencyLimit, nextAssetIndex < assets.count {
                if Task.isCancelled || stopRequested {
                    group.cancelAll()
                    break
                }
                let exportIndex = nextAssetIndex
                let descriptor = assets[nextAssetIndex]
                nextAssetIndex += 1
                inFlightExportCount += 1
                group.addTask {
                    (
                        exportIndex,
                        await exportPipelineResult(
                            descriptor: descriptor,
                            exportSource: exportSource,
                            sessionID: sessionID,
                            telemetryClient: telemetryClient
                        )
                    )
                }
            }

            while inFlightExportCount > 0 {
                guard let (completedIndex, exportResult) = await group.next() else {
                    break
                }
                inFlightExportCount -= 1
                pendingResultsByIndex[completedIndex] = exportResult
                while let orderedResult = pendingResultsByIndex.removeValue(forKey: nextResultIndexToEnqueue) {
                    await queue.enqueue(orderedResult)
                    nextResultIndexToEnqueue += 1
                }

                if Task.isCancelled || stopRequested {
                    group.cancelAll()
                    continue
                }
                if nextAssetIndex >= assets.count {
                    continue
                }

                let exportIndex = nextAssetIndex
                let descriptor = assets[nextAssetIndex]
                nextAssetIndex += 1
                inFlightExportCount += 1
                group.addTask {
                    (
                        exportIndex,
                        await exportPipelineResult(
                            descriptor: descriptor,
                            exportSource: exportSource,
                            sessionID: sessionID,
                            telemetryClient: telemetryClient
                        )
                    )
                }
            }
        }

        await queue.finish()
    }

    private func processUploadResult(
        _ uploadResult: PreparedTransferUploadResult,
        desktop: TrustedDesktopRecord,
        totalCount: Int,
        transferredCount: inout Int,
        failedCount: inout Int,
        skippedCount: inout Int,
        stageMetrics: inout TransferStageMetrics,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async -> TransferSnapshot? {
        if uploadResult.existenceCheckDurationSeconds > 0 {
            stageMetrics.existenceCheckDurations.append(uploadResult.existenceCheckDurationSeconds)
        }
        if uploadResult.uploadDurationSeconds > 0 {
            stageMetrics.uploadDurations.append(uploadResult.uploadDurationSeconds)
        }
        processedPreparedTransferBytes += max(uploadResult.preparedAsset.exportedAsset.fileSize, 0)
        let assetSummary = TransferDebugLogger.assetSummary(for: uploadResult.preparedAsset.exportedAsset.descriptor)
        if uploadResult.terminalFailureCode == .diskFull {
            failedCount += 1
            let diskFullMessage = uploadResult.terminalFailureMessage
                ?? "Desktop storage is full. Free up disk space on this PC and retry mobile backup."
            TransferDebugLogger.error("Transfer failed for \(assetSummary) error=\(diskFullMessage)")
            cleanupExportedAsset(uploadResult.preparedAsset.exportedAsset)
            return await makeTerminalFailureSnapshot(
                desktop: desktop,
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount,
                skippedCount: skippedCount,
                message: diskFullMessage
            )
        }
        if let existingMatch = uploadResult.existingMatch {
            transferredCount += 1
            skippedCount += 1
            successfullyTransferredAssetIDs.insert(uploadResult.preparedAsset.exportedAsset.descriptor.assetID)
            TransferDebugLogger.debug(
                "Skipped upload after desktop signature hit \(assetSummary) local_relative_path=\(existingMatch.localRelativePath)"
            )
        } else if let response = uploadResult.response {
            switch response.status {
            case .stored, .skipped:
                switch response.status {
                case .stored:
                    transferredCount += 1
                    nonSkippedTransferredBytesForSpeed += max(uploadResult.preparedAsset.exportedAsset.fileSize, 0)
                    successfullyTransferredAssetIDs.insert(uploadResult.preparedAsset.exportedAsset.descriptor.assetID)
                    TransferDebugLogger.debug(
                        "Transferred asset \(assetSummary) response=\(TransferDebugLogger.responseSummary(response))"
                    )
                case .skipped:
                    transferredCount += 1
                    skippedCount += 1
                    successfullyTransferredAssetIDs.insert(uploadResult.preparedAsset.exportedAsset.descriptor.assetID)
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
        } else {
            failedCount += 1
            let errorDescription = uploadResult.errorDescription ?? "unknown upload error"
            TransferDebugLogger.error("Transfer failed for \(assetSummary) error=\(errorDescription)")
        }

        cleanupExportedAsset(uploadResult.preparedAsset.exportedAsset)
        await recordProgressUpdate(
            desktop: desktop,
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            progress: progress
        )
        return nil
    }

    private func makePausedSnapshot(
        transport: TransferTransport,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        skippedCount: Int,
        sessionID: String
    ) -> TransferSnapshot {
        TransferDebugLogger.info(
            "Transfer stop requested session_id=\(sessionID) transferred=\(transferredCount) failed=\(failedCount)"
        )
        return TransferSnapshot(
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            transport: transport,
            transferSpeedText: currentTransferSpeedText(),
            etaMinutes: nil,
            statusMessage: "Backup stopped. In-flight work was canceled to release resources quickly.",
            guidanceMessage: "Start a new backup session to continue sending any remaining accessible items.",
            isIncompleteLibrary: false
        )
    }

    private func makeTerminalFailureSnapshot(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        skippedCount: Int,
        message: String
    ) async -> TransferSnapshot {
        let transport = await resolvedTransport(for: desktop)
        let failedSnapshot = TransferSnapshot(
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            transport: transport,
            transferSpeedText: currentTransferSpeedText(),
            etaMinutes: nil,
            statusMessage: message,
            guidanceMessage: "Free up disk space on the desktop, then start a new backup session.",
            isIncompleteLibrary: false
        )
        let failedSnapshotWithLiveTransports = await applyingLiveTransports(
            to: failedSnapshot,
            desktop: desktop
        )
        currentSnapshot = failedSnapshotWithLiveTransports
        return failedSnapshotWithLiveTransports
    }

    private func recordProgressUpdate(
        desktop: TrustedDesktopRecord,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        skippedCount: Int,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async {
        let transport = await resolvedTransport(for: desktop)
        let processedCount = min(transferredCount + failedCount, totalCount)
        TransferDebugLogger.debug(
            "Updated transfer progress processed=\(processedCount) total=\(totalCount) transferred=\(transferredCount) failed=\(failedCount) skipped=\(skippedCount)"
        )
        if processedCount == totalCount || (processedCount > 0 && processedCount.isMultiple(of: 25)) {
            logTransferMemoryUsage(
                event: "transfer_progress",
                processedCount: processedCount,
                totalCount: totalCount
            )
        }
        let updatedSnapshot = makeProgressSnapshot(
            transport: transport,
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount
        )
        let updatedSnapshotWithLiveTransports = await applyingLiveTransports(
            to: updatedSnapshot,
            desktop: desktop
        )
        currentSnapshot = updatedSnapshotWithLiveTransports
        progress(updatedSnapshotWithLiveTransports)
    }

    private func recordChunkTransferProgress(
        bytes: Int,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async {
        guard bytes > 0, !stopRequested else {
            return
        }
        recordTransferredBytes(bytes)
        guard var snapshot = currentSnapshot else {
            return
        }
        snapshot.transferSpeedText = currentTransferSpeedText()
        snapshot.etaMinutes = currentETAMinutes(
            transferredCount: snapshot.transferredCount,
            totalCount: snapshot.totalCount,
            failedCount: snapshot.failedCount
        )
        currentSnapshot = snapshot
        progress(snapshot)
    }

    private func resolvedTransport(for desktop: TrustedDesktopRecord) async -> TransferTransport {
        guard let transportResolver else {
            return desktop.transport
        }
        return await transportResolver.resolveDesktopTransport(for: desktop)
    }

    private func applyingLiveTransports(
        to snapshot: TransferSnapshot,
        desktop: TrustedDesktopRecord
    ) async -> TransferSnapshot {
        guard let liveTransportResolver else {
            return snapshot
        }
        let resolvedLiveTransports = await liveTransportResolver.resolveLiveTransports(for: desktop)
        var updatedSnapshot = snapshot
        updatedSnapshot.liveTransports = normalizedLiveTransports(
            resolvedLiveTransports,
            primaryTransport: snapshot.transport
        )
        return updatedSnapshot
    }

    private func normalizedLiveTransports(
        _ resolvedLiveTransports: [TransferTransport],
        primaryTransport: TransferTransport
    ) -> [TransferTransport] {
        var orderedLiveTransports: [TransferTransport] = []
        let preferredDisplayOrder: [TransferTransport] = [.usb, .lan]
        for candidateTransport in preferredDisplayOrder {
            if resolvedLiveTransports.contains(candidateTransport) || candidateTransport == primaryTransport {
                orderedLiveTransports.append(candidateTransport)
            }
        }
        if orderedLiveTransports.isEmpty {
            orderedLiveTransports.append(primaryTransport)
        }
        return orderedLiveTransports
    }

    private func makeProgressSnapshot(
        transport: TransferTransport,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        skippedCount: Int
    ) -> TransferSnapshot {
        let processedCount = min(transferredCount + failedCount, totalCount)
        return TransferSnapshot(
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            transport: transport,
            transferSpeedText: currentTransferSpeedText(),
            etaMinutes: currentETAMinutes(
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount
            ),
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

    private func logTransferMemoryUsage(
        event: String,
        processedCount: Int? = nil,
        totalCount: Int? = nil
    ) {
        guard let memorySnapshot = ProcessMemorySnapshot.capture() else {
            TransferDebugLogger.warning(
                "Transfer memory telemetry unavailable event=\(event) upload_concurrency_limit=\(uploadConcurrencyLimit)"
            )
            return
        }
        var fields = [
            "Transfer memory telemetry",
            "event=\(event)",
            "footprint=\(formattedByteCount(memorySnapshot.physicalFootprintBytes))",
            "resident=\(formattedByteCount(memorySnapshot.residentSizeBytes))",
            "upload_concurrency_limit=\(uploadConcurrencyLimit)",
        ]
        if let processedCount, let totalCount {
            fields.append("processed=\(processedCount)")
            fields.append("total=\(totalCount)")
        }
        TransferDebugLogger.info(fields.joined(separator: " "))
    }

    private func formattedByteCount(_ bytes: UInt64) -> String {
        let cappedBytes = min(bytes, UInt64(Int64.max))
        return ByteCountFormatter.string(
            fromByteCount: Int64(cappedBytes),
            countStyle: .memory
        )
    }

    private func logTransferStageMetrics(
        desktop: TrustedDesktopRecord,
        totalCount: Int,
        transferredCount: Int,
        failedCount: Int,
        runDurationSeconds: Double,
        stageMetrics: TransferStageMetrics
    ) {
        let exportSummary = summarizeStageDurations(stageMetrics.exportDurations)
        let existenceSummary = summarizeStageDurations(stageMetrics.existenceCheckDurations)
        let uploadSummary = summarizeStageDurations(stageMetrics.uploadDurations)
        let stageAggregateSeconds = exportSummary.totalSeconds + existenceSummary.totalSeconds + uploadSummary.totalSeconds
        let bottleneckStage = [
            ("export", exportSummary.totalSeconds),
            ("existence", existenceSummary.totalSeconds),
            ("upload", uploadSummary.totalSeconds),
        ].max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? "none"
        let throughputAssetsPerSecond = runDurationSeconds > 0
            ? Double(transferredCount) / runDurationSeconds
            : 0

        TransferDebugLogger.info(
            String(
                format:
                    "Transfer stage metrics session_id=%@ total=%d transferred=%d failed=%d run_s=%.3f throughput_assets_s=%.3f stage_aggregate_s=%.3f bottleneck=%@ export(count=%d avg_ms=%.1f p50_ms=%.1f p95_ms=%.1f total_s=%.3f) existence(count=%d avg_ms=%.1f p50_ms=%.1f p95_ms=%.1f total_s=%.3f) upload(count=%d avg_ms=%.1f p50_ms=%.1f p95_ms=%.1f total_s=%.3f)",
                desktop.lastSessionID,
                totalCount,
                transferredCount,
                failedCount,
                runDurationSeconds,
                throughputAssetsPerSecond,
                stageAggregateSeconds,
                bottleneckStage,
                exportSummary.count,
                exportSummary.averageMilliseconds,
                exportSummary.p50Milliseconds,
                exportSummary.p95Milliseconds,
                exportSummary.totalSeconds,
                existenceSummary.count,
                existenceSummary.averageMilliseconds,
                existenceSummary.p50Milliseconds,
                existenceSummary.p95Milliseconds,
                existenceSummary.totalSeconds,
                uploadSummary.count,
                uploadSummary.averageMilliseconds,
                uploadSummary.p50Milliseconds,
                uploadSummary.p95Milliseconds,
                uploadSummary.totalSeconds
            )
        )
    }

    private func summarizeStageDurations(_ durations: [Double]) -> StageDurationSummary {
        let normalizedDurations = durations.map { max($0, 0) }
        guard !normalizedDurations.isEmpty else {
            return StageDurationSummary(
                count: 0,
                averageMilliseconds: 0,
                p50Milliseconds: 0,
                p95Milliseconds: 0,
                totalSeconds: 0
            )
        }
        let sortedDurations = normalizedDurations.sorted()
        let totalSeconds = sortedDurations.reduce(0, +)
        let averageSeconds = totalSeconds / Double(sortedDurations.count)
        return StageDurationSummary(
            count: sortedDurations.count,
            averageMilliseconds: averageSeconds * 1_000,
            p50Milliseconds: percentileDuration(sortedDurations, percentile: 0.50) * 1_000,
            p95Milliseconds: percentileDuration(sortedDurations, percentile: 0.95) * 1_000,
            totalSeconds: totalSeconds
        )
    }

    private func percentileDuration(_ sortedDurations: [Double], percentile: Double) -> Double {
        guard !sortedDurations.isEmpty else {
            return 0
        }
        let clampedPercentile = min(max(percentile, 0), 1)
        let rawIndex = Double(sortedDurations.count - 1) * clampedPercentile
        let index = min(max(Int(rawIndex.rounded(.up)), 0), sortedDurations.count - 1)
        return sortedDurations[index]
    }

    private func resetTransferSpeedWindow() {
        transferSpeedSamples.removeAll(keepingCapacity: false)
    }

    private func currentETAMinutes(
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int
    ) -> Double? {
        guard transferRunStartedAtUptimeSeconds != nil else {
            return nil
        }
        guard totalCount > 0 else {
            return nil
        }
        let processedCount = min(max(transferredCount + failedCount, 0), totalCount)
        guard processedCount > 0 else {
            return nil
        }
        let averageBytesPerProcessedItem = Double(max(processedPreparedTransferBytes, 1)) / Double(processedCount)
        let estimatedTotalBytes = max(
            Double(totalPreparedTransferBytes),
            averageBytesPerProcessedItem * Double(totalCount)
        )
        let remainingSizeBytes = max(Int(estimatedTotalBytes.rounded(.up)) - processedPreparedTransferBytes, 0)
        guard remainingSizeBytes > 0 else {
            return nil
        }
        let averageSpeedBytesPerSecond = currentTransferSpeedBytesPerSecond()
        guard averageSpeedBytesPerSecond > 0 else {
            return nil
        }
        let remainingSeconds = Double(remainingSizeBytes) / averageSpeedBytesPerSecond
        guard remainingSeconds.isFinite, remainingSeconds > 0 else {
            return nil
        }
        return remainingSeconds / 60.0
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
        let speedMBps = currentTransferSpeedBytesPerSecond() / 1_048_576.0
        return String(format: "%.2f MB/s", speedMBps)
    }

    private func currentTransferSpeedBytesPerSecond() -> Double {
        let now = Date()
        pruneTransferSpeedSamples(now: now)
        let totalBytes = transferSpeedSamples.reduce(0) { partial, sample in
            partial + sample.bytes
        }
        let sampledSpeed = Double(totalBytes) / Self.transferSpeedWindowSeconds
        if sampledSpeed > 0 {
            return sampledSpeed
        }
        guard
            let transferRunStartedAtUptimeSeconds,
            nonSkippedTransferredBytesForSpeed > 0
        else {
            return 0
        }
        let elapsedSeconds = max(ProcessInfo.processInfo.systemUptime - transferRunStartedAtUptimeSeconds, 0)
        guard elapsedSeconds > 0 else {
            return 0
        }
        return Double(nonSkippedTransferredBytesForSpeed) / elapsedSeconds
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
