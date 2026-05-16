import Foundation
import Combine

protocol BackupSessionStore: Sendable {
    func loadBackupSession() async -> BackupSession?
    func saveBackupSession(_ session: BackupSession?) async
}

@MainActor
protocol BackupSessionProviding: AnyObject {
    var backupSession: BackupSession? { get }
    var backupSessionPublisher: AnyPublisher<BackupSession?, Never> { get }

    func load() async
    func saveBackupSession(_ session: BackupSession?) async
}

@MainActor
extension BackupSessionProviding {
    func saveBackupSession(
        status: BackupSessionStatus,
        sessionID: String? = nil,
        desktopName: String? = nil
    ) async {
        let currentSession = backupSession
        await saveBackupSession(
            BackupSession(
                sessionID: sessionID ?? currentSession?.sessionID,
                desktopName: desktopName ?? currentSession?.desktopName,
                status: status,
                updatedAt: Date()
            )
        )
    }
}

protocol PairingService: Sendable {
    func primeNetworkAccess() async
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus
}

protocol PairingBootstrapClient: Sendable {
    func primeInternetAccess() async
    func claimPairing(at endpoint: URL, request: PairingClaimRequest) async throws -> PairingClaimResponse
    func fetchPairingState(at endpoint: URL, request: PairingStateRequest) async throws -> PairingClaimResponse
}

protocol PairingUSBBootstrapClient: Sendable {
    func claimPairing(using payload: PairingQRCodePayload, request: PairingClaimRequest) async throws -> PairingClaimResponse
    func fetchPairingState(using payload: PairingQRCodePayload, request: PairingStateRequest) async throws -> PairingClaimResponse
}

protocol LocalDeviceIdentityProviding: Sendable {
    func currentIdentity() async -> LocalDeviceIdentity
}

protocol TrustedDesktopStore: Sendable {
    func loadTrustedDesktop() async -> TrustedDesktopRecord?
    func saveTrustedDesktop(_ record: TrustedDesktopRecord) async
}

protocol QRCodePayloadDecoding: Sendable {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError>
}

protocol PermissionService: Sendable {
    func loadPermissionSummary() async -> PermissionSummary
    func requestMediaAccess() async -> PermissionScope
    func removeAfterBackupEnabled() async -> Bool
    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async
}

extension PermissionService {
    func requestMediaAccess() async -> PermissionScope {
        await loadPermissionSummary().mediaScope
    }
}

protocol TransferService: Sendable {
    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot
    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason
    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot
    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot
    func progressSnapshot() async -> TransferSnapshot?
    func stageTransferSnapshot(_ snapshot: TransferSnapshot) async
    func transferCompletionState() async -> TransferCompletionState?
    func stageTransferCompletionState(_ completionState: TransferCompletionState?) async
    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult
    func handleAppDidBecomeActive() async
    func handleMemoryWarning() async
}

extension TransferService {
    func handleAppDidBecomeActive() async {}
}

enum TransferAssetCleanupResult: Equatable, Sendable {
    case skipped
    case removed(Int)
    case failed(message: String)
}

struct TransferCompletionState: Equatable, Sendable {
    let snapshot: TransferSnapshot
    let cleanupResult: TransferAssetCleanupResult
    let completedAt: Date
    let sessionDuration: TimeInterval?
}

protocol TelemetryClient: Sendable {
    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async
    func begin(span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) async
    func end(
        span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    ) async
    func increment(metric: MobileTelemetryMetric, by value: Int, attributes: MobileTelemetryAttributes) async
    func currentTraceContext() async -> MobileTraceContext?
    func withSpan<T: Sendable>(
        name: String,
        attributes: MobileTelemetryAttributes,
        operation: @Sendable () async throws -> T
    ) async throws -> T
    func forceFlush() async
}

extension TelemetryClient {
    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        _ = event
        _ = attributes
    }

    func record(event: MobileTelemetryEvent) async {
        await record(event: event, attributes: [:])
    }

    func begin(span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes = [:]) async {
        _ = span
        _ = attributes
    }

    func end(
        span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:],
        status: MobileTelemetrySpanStatus? = nil
    ) async {
        _ = span
        _ = attributes
        _ = status
    }

    func increment(
        metric: MobileTelemetryMetric,
        by value: Int = 1,
        attributes: MobileTelemetryAttributes = [:]
    ) async {
        _ = metric
        _ = value
        _ = attributes
    }

    func currentTraceContext() async -> MobileTraceContext? { nil }

    func withSpan<T: Sendable>(
        name: String,
        attributes: MobileTelemetryAttributes,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        _ = name
        _ = attributes
        return try await operation()
    }

    func forceFlush() async {}
}

enum MobileTelemetryEvent: String, Sendable {
    case appLaunched
    case pageViewed
    case dialogViewed
    case interactionTriggered
    case scanStarted
    case pairingStarted
    case pairingSucceeded
    case pairingFailed
    case backupPreflightStarted
    case mediaAccessPromptShown
    case mediaAccessContinued
    case lowBatteryPromptShown
    case lowBatteryContinued
    case lowBatteryCanceled
    case removeAfterBackupPromptShown
    case removeAfterBackupPreferenceSelected
    case transferStarted
    case transferStopRequested
    case memoryWarningReceived
    case transferStopped
    case transferCompleted
}

enum MobileTelemetrySpan: String, Sendable {
    case backupSession = "mobile.backup.session"
    case pairingFlow = "mobile.backup.pairing"
    case backupPreflight = "mobile.backup.preflight"
    case transferFlow = "mobile.backup.transfer"
}

enum MobileTelemetryMetric: String, Sendable {
    case backupAttempts = "mobile.backup.attempts"
    case backupSuccesses = "mobile.backup.successes"
    case backupFailures = "mobile.backup.failures"
    case backupCompletedItems = "mobile.backup.completed_items"
}

enum MobileTelemetrySpanStatus: Sendable {
    case ok
    case error(String)
}

struct MobileTraceContext: Equatable, Sendable {
    let traceParent: String
    let traceState: String?
}

struct NoOpTelemetryClient: TelemetryClient {}

func traceContextPayloadFields(_ traceContext: MobileTraceContext?) -> [String: Any] {
    guard let traceContext else {
        return [:]
    }
    var payload: [String: Any] = [
        "traceparent": traceContext.traceParent,
    ]
    if let traceState = traceContext.traceState, !traceState.isEmpty {
        payload["tracestate"] = traceState
    }
    return payload
}

typealias MobileTelemetryAttributes = [String: MobileTelemetryAttributeValue]

enum MobileTelemetryAttributeValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
}

enum PairingProtocol {
    static let schema = "dtis.mobile-pairing.v1"
}

extension PairingService {
    func primeNetworkAccess() async {}
}

extension PairingBootstrapClient {
    func primeInternetAccess() async {}

    func fetchPairingState(at endpoint: URL, request: PairingStateRequest) async throws -> PairingClaimResponse {
        _ = endpoint
        _ = request
        throw PairingServiceError.transport(message: "Desktop pairing state polling is unavailable.")
    }
}

extension PairingUSBBootstrapClient {
    func fetchPairingState(using payload: PairingQRCodePayload, request: PairingStateRequest) async throws -> PairingClaimResponse {
        _ = payload
        _ = request
        throw PairingServiceError.transport(message: "Desktop USB pairing state polling is unavailable.")
    }
}

extension TransferService {
    func handleMemoryWarning() async {}
}

enum PairingBootstrapResponseStatus: String, Codable, Sendable {
    case accepted
    case rejected
    case expired
}

enum PairingWireState: String, Codable, Sendable {
    case pendingPairing = "pending_pairing"
    case pairingMismatched = "pairing_mismatched"
    case pairingCompleted = "pairing_completed"
    case pairingExpired = "pairing_expired"
    case pairingStopped = "pairing_stopped"

    var backupFlowState: MobileBackupFlowState {
        switch self {
        case .pendingPairing:
            return .pendingPairing
        case .pairingMismatched:
            return .pairingMismatched
        case .pairingCompleted:
            return .pairingCompleted
        case .pairingExpired:
            return .pairingExpired
        case .pairingStopped:
            return .pairingStopped
        }
    }
}

struct PairingClaimRequest: Codable, Sendable {
    var schema = PairingProtocol.schema
    var sessionID: String
    var oneTimePasscode: String
    var platform: String
    var deviceUUID: String
    var deviceName: String
    var installID: String
    var clientNonce: String

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "sid"
        case oneTimePasscode = "opt"
        case platform
        case deviceUUID = "device_uuid"
        case deviceName = "device_name"
        case installID = "install_id"
        case clientNonce = "client_nonce"
    }
}

struct PairingStateRequest: Codable, Sendable {
    var schema = PairingProtocol.schema
    var sessionID: String
    var deviceUUID: String

    enum CodingKeys: String, CodingKey {
        case schema
        case sessionID = "session_id"
        case deviceUUID = "device_uuid"
    }
}

struct PairingClaimResponse: Codable, Sendable {
    var schema: String
    var backupState: PairingWireState
    var message: String
    var sessionID: String?
    var desktopDeviceID: String?
    var desktopName: String?
    var deviceUUID: String?
    var folderID: Int?
    var folderPath: String?
    var transport: String?
    var pairedAt: Date?
    var serverNonce: String?

    enum CodingKeys: String, CodingKey {
        case schema
        case backupState = "backup_state"
        case legacyStatus = "status"
        case legacyPairingState = "pairing_state"
        case message
        case sessionID = "session_id"
        case desktopDeviceID = "desktop_device_id"
        case desktopName = "desktop_name"
        case deviceUUID = "device_uuid"
        case folderID = "folder_id"
        case folderPath = "folder_path"
        case transport
        case pairedAt = "paired_at"
        case serverNonce = "server_nonce"
    }

    init(
        schema: String,
        backupState: PairingWireState,
        message: String,
        sessionID: String?,
        desktopDeviceID: String?,
        desktopName: String?,
        deviceUUID: String?,
        folderID: Int?,
        folderPath: String?,
        transport: String?,
        pairedAt: Date?,
        serverNonce: String?
    ) {
        self.schema = schema
        self.backupState = backupState
        self.message = message
        self.sessionID = sessionID
        self.desktopDeviceID = desktopDeviceID
        self.desktopName = desktopName
        self.deviceUUID = deviceUUID
        self.folderID = folderID
        self.folderPath = folderPath
        self.transport = transport
        self.pairedAt = pairedAt
        self.serverNonce = serverNonce
    }

    init(
        schema: String,
        status: PairingBootstrapResponseStatus,
        pairingState: PairingWireState? = nil,
        message: String,
        sessionID: String?,
        desktopDeviceID: String?,
        desktopName: String?,
        deviceUUID: String?,
        folderID: Int?,
        folderPath: String?,
        transport: String?,
        pairedAt: Date?,
        serverNonce: String?
    ) {
        self.init(
            schema: schema,
            backupState: pairingState ?? PairingClaimResponse.backupState(from: status),
            message: message,
            sessionID: sessionID,
            desktopDeviceID: desktopDeviceID,
            desktopName: desktopName,
            deviceUUID: deviceUUID,
            folderID: folderID,
            folderPath: folderPath,
            transport: transport,
            pairedAt: pairedAt,
            serverNonce: serverNonce
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        if let explicitBackupState = try container.decodeIfPresent(PairingWireState.self, forKey: .backupState) {
            backupState = explicitBackupState
        } else if let legacyPairingState = try container.decodeIfPresent(PairingWireState.self, forKey: .legacyPairingState) {
            backupState = legacyPairingState
        } else if let legacyStatus = try container.decodeIfPresent(PairingBootstrapResponseStatus.self, forKey: .legacyStatus) {
            backupState = PairingClaimResponse.backupState(from: legacyStatus)
        } else {
            throw PairingServiceError.decoding(message: "Desktop pairing response is missing backup_state.")
        }
        message = try container.decode(String.self, forKey: .message)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        desktopDeviceID = try container.decodeIfPresent(String.self, forKey: .desktopDeviceID)
        desktopName = try container.decodeIfPresent(String.self, forKey: .desktopName)
        deviceUUID = try container.decodeIfPresent(String.self, forKey: .deviceUUID)
        folderID = try container.decodeIfPresent(Int.self, forKey: .folderID)
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
        transport = try container.decodeIfPresent(String.self, forKey: .transport)
        pairedAt = try container.decodeIfPresent(Date.self, forKey: .pairedAt)
        serverNonce = try container.decodeIfPresent(String.self, forKey: .serverNonce)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(backupState, forKey: .backupState)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(desktopDeviceID, forKey: .desktopDeviceID)
        try container.encodeIfPresent(desktopName, forKey: .desktopName)
        try container.encodeIfPresent(deviceUUID, forKey: .deviceUUID)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encodeIfPresent(folderPath, forKey: .folderPath)
        try container.encodeIfPresent(transport, forKey: .transport)
        try container.encodeIfPresent(pairedAt, forKey: .pairedAt)
        try container.encodeIfPresent(serverNonce, forKey: .serverNonce)
    }

    private static func backupState(from status: PairingBootstrapResponseStatus) -> PairingWireState {
        switch status {
        case .accepted:
            return .pairingCompleted
        case .expired:
            return .pairingExpired
        case .rejected:
            return .pairingStopped
        }
    }
}

struct LocalDeviceIdentity: Codable, Equatable, Sendable {
    var installID: String
    var deviceUUID: String
    var deviceName: String
    var platform: String
}

struct TrustedDesktopRecord: Codable, Equatable, Sendable {
    var desktopDeviceID: String
    var desktopName: String
    var endpointURL: URL
    var mobileDeviceUUID: String
    var sharedKeyBase64: String
    var transport: TransferTransport
    var lastSessionID: String
    var usbOneTimePasscode: String? = nil
    var usbSuggestedPort: Int? = nil
    var pairedAt: Date
}

enum PairingDateCodec {
    static func string(from date: Date) -> String {
        internetDateTimeFormatter().string(from: date)
    }

    static func date(from value: String) -> Date? {
        if let decodedDate = internetDateTimeFormatter().date(from: value) {
            return decodedDate
        }
        return fractionalSecondsFormatter().date(from: value)
    }

    private static func internetDateTimeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func fractionalSecondsFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

enum PairingServiceError: Error, Sendable {
    case invalidHTTPResponse
    case unsupportedResponseSchema
    case invalidAcceptedResponse
    case rejected(message: String)
    case expired(message: String)
    case transport(message: String)
    case decoding(message: String)
}

enum QRCodePayloadDecoderError: Error, Equatable, Sendable {
    case emptyPayload
    case invalidURL
    case invalidHost
    case invalidSchemaVersion
    case invalidEndpoint
    case invalidSuggestedUSBPort
    case missingField(String)

    var message: String {
        switch self {
        case .emptyPayload:
            return "Scan the desktop pairing QR code to continue."
        case .invalidURL:
            return "The QR code is not a valid deep link."
        case .invalidHost:
            return "The QR code does not point at the expected mobile deep link host."
        case .invalidSchemaVersion:
            return "The QR payload uses an unsupported schema version."
        case .invalidEndpoint:
            return "The QR payload contains an invalid desktop endpoint target."
        case .invalidSuggestedUSBPort:
            return "The QR payload contains an invalid USB bootstrap port."
        case .missingField(let field):
            return "The QR payload is missing the required field '\(field)'."
        }
    }
}

struct URLQueryQRCodePayloadDecoder: QRCodePayloadDecoding {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        let trimmedValue = scannedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return .failure(.emptyPayload)
        }

        guard let url = URL(string: trimmedValue),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return .failure(.invalidURL)
        }

        guard components.scheme == "https", components.host == "dl.boldman.net" else {
            return .failure(.invalidHost)
        }

        let queryItems = components.queryItems ?? []

        func item(named name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        guard let versionString = item(named: "v"),
              let schemaVersion = Int(versionString)
        else {
            return .failure(.missingField("v"))
        }

        guard schemaVersion == 1 || schemaVersion == 2 else {
            return .failure(.invalidSchemaVersion)
        }

        guard let endpointTargetsValue = item(named: "ept") else {
            return .failure(.missingField("ept"))
        }

        let endpointTargets = endpointTargetsValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !endpointTargets.isEmpty,
              endpointTargets.count <= PairingQRCodePayload.maxEndpointTargets,
              endpointTargets.allSatisfy({ PairingQRCodePayload.bootstrapURL(for: $0) != nil })
        else {
            return .failure(.invalidEndpoint)
        }

        guard let sessionID = item(named: "sid") else {
            return .failure(.missingField("sid"))
        }

        guard let oneTimePasscode = item(named: "opt") else {
            return .failure(.missingField("opt"))
        }

        var suggestedUSBPort: Int? = nil
        if let suggestedUSBPortValue = item(named: "usp") {
            guard let parsedPort = Int(suggestedUSBPortValue), (1 ... 65535).contains(parsedPort) else {
                return .failure(.invalidSuggestedUSBPort)
            }
            suggestedUSBPort = parsedPort
        }
        if schemaVersion >= 2, suggestedUSBPort == nil {
            return .failure(.missingField("usp"))
        }

        return .success(
            PairingQRCodePayload(
                schemaVersion: schemaVersion,
                endpointTargets: endpointTargets,
                sessionID: sessionID,
                oneTimePasscode: oneTimePasscode,
                suggestedUSBPort: suggestedUSBPort
            )
        )
    }
}
