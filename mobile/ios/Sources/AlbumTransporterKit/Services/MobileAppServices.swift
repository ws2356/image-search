import Foundation

protocol AppStateStore: Sendable {
    func loadLaunchSnapshot() async -> LaunchSnapshot
    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async
}

protocol PairingService: Sendable {
    func primeNetworkAccess() async
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus
}

protocol PairingBootstrapClient: Sendable {
    func primeInternetAccess() async
    func claimPairing(at endpoint: URL, request: PairingClaimRequest) async throws -> PairingClaimResponse
}

protocol PairingUSBBootstrapClient: Sendable {
    func claimPairing(using payload: PairingQRCodePayload, request: PairingClaimRequest) async throws -> PairingClaimResponse
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
}

protocol TransferService: Sendable {
    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot
    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason
    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot
    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot
    func progressSnapshot() async -> TransferSnapshot?
    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult
}

enum TransferAssetCleanupResult: Equatable, Sendable {
    case skipped
    case removed(Int)
    case failed(message: String)
}

protocol TelemetryClient: Sendable {
    func record(event: MobileTelemetryEvent) async
}

enum MobileTelemetryEvent: String, Sendable {
    case appLaunched
    case scanStarted
    case pairingStarted
    case pairingSucceeded
    case pairingFailed
    case transferStarted
    case transferStopped
    case resumeTapped
    case transferCompleted
}

enum PairingProtocol {
    static let schema = "dtis.mobile-pairing.v1"
}

extension PairingService {
    func primeNetworkAccess() async {}
}

extension PairingBootstrapClient {
    func primeInternetAccess() async {}
}

enum PairingBootstrapResponseStatus: String, Codable, Sendable {
    case accepted
    case rejected
    case expired
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

struct PairingClaimResponse: Codable, Sendable {
    var schema: String
    var status: PairingBootstrapResponseStatus
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
        case status
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
