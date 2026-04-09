import Foundation

protocol AppStateStore: Sendable {
    func loadLaunchSnapshot() async -> LaunchSnapshot
    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async
}

protocol PairingService: Sendable {
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus
}

protocol QRCodePayloadDecoding: Sendable {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError>
}

protocol PermissionService: Sendable {
    func loadPermissionSummary() async -> PermissionSummary
}

protocol TransferService: Sendable {
    func startTransfer() async -> TransferSnapshot
    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason
    func resumeTransfer(from snapshot: TransferSnapshot) async -> TransferSnapshot
    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot
}

protocol TelemetryClient: Sendable {
    func record(event: MobileTelemetryEvent) async
}

enum MobileTelemetryEvent: String, Sendable {
    case appLaunched
    case scanStarted
    case pairingStarted
    case pairingSucceeded
    case transferStarted
    case transferStopped
    case resumeTapped
    case transferCompleted
}

enum QRCodePayloadDecoderError: Error, Equatable, Sendable {
    case invalidURL
    case invalidHost
    case invalidSchemaVersion
    case missingField(String)

    var message: String {
        switch self {
        case .invalidURL:
            return "The QR code is not a valid deep link."
        case .invalidHost:
            return "The QR code does not point at the expected mobile deep link host."
        case .invalidSchemaVersion:
            return "The QR payload uses an unsupported schema version."
        case .missingField(let field):
            return "The QR payload is missing the required field '\(field)'."
        }
    }
}

struct URLQueryQRCodePayloadDecoder: QRCodePayloadDecoding {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        guard let url = URL(string: scannedValue),
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

        guard schemaVersion == 1 else {
            return .failure(.invalidSchemaVersion)
        }

        guard let endpointString = item(named: "endpoint"),
              let bootstrapURL = URL(string: endpointString)
        else {
            return .failure(.missingField("endpoint"))
        }

        guard let pairingID = item(named: "pairing_id") else {
            return .failure(.missingField("pairing_id"))
        }

        guard let secret = item(named: "secret") else {
            return .failure(.missingField("secret"))
        }

        return .success(
            PairingQRCodePayload(
                schemaVersion: schemaVersion,
                bootstrapURL: bootstrapURL,
                pairingID: pairingID,
                secret: secret
            )
        )
    }
}
