import Foundation

enum AppRoute: Equatable, Sendable {
    case home
    case scan
    case genericScan
    case pair(qrString: String)
    case permissions
    case transfer
    case completed
    case error(ErrorSummary)
}

extension AppRoute {
    var routeName: String {
        switch self {
        case .home:
            return "home"
        case .scan:
            return "scan"
        case .genericScan:
            return "genericScan"
        case .pair:
            return "pair"
        case .permissions:
            return "permissions"
        case .transfer:
            return "transfer"
        case .completed:
            return "completed"
        case .error:
            return "error"
        }
    }
}

struct ErrorSummary: Equatable, Sendable, Codable {
    var title: String
    var message: String

    static let generic = ErrorSummary(
        title: "Something went wrong",
        message: "AuBackup hit an unexpected issue. Try starting a new backup session, or return home."
    )
}

enum PermissionScope: String, Equatable, Sendable, Codable {
    case full
    case limited
    case denied

    var title: String {
        switch self {
        case .full:
            return "Full Library Access"
        case .limited:
            return "Limited Library Access"
        case .denied:
            return "Media Access Denied"
        }
    }

    var detail: String {
        switch self {
        case .full:
            return "The app can include all eligible local photos and videos."
        case .limited:
            return "Only selected photos and videos are included. Grant full access to include your entire eligible library in this backup."
        case .denied:
            return "Backup cannot begin until media library access is granted."
        }
    }

    var isIncomplete: Bool {
        self != .full
    }
}

enum TransferTransport: String, Equatable, Hashable, Sendable, Codable {
    case lan
    case usb

    var title: String {
        switch self {
        case .lan:
            return "Wi-Fi"
        case .usb:
            return "USB"
        }
    }

    var systemImage: String {
        switch self {
        case .lan:
            return "wifi"
        case .usb:
            return "cable.connector"
        }
    }
}

struct BackupSession: Equatable, Sendable, Codable {
    var sessionID: String?
    var desktopName: String?
    var status: MobileBackupFlowState
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case sessionID
        case desktopName
        case status
        case updatedAt
    }

    init(
        sessionID: String?,
        desktopName: String?,
        status: MobileBackupFlowState,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.desktopName = desktopName
        self.status = status
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        desktopName = try container.decodeIfPresent(String.self, forKey: .desktopName)
        status = try container.decode(MobileBackupFlowState.self, forKey: .status)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct PairingQRCodePayload: Codable, Equatable, Sendable {
    static let maxEndpointTargets = 5

    var schemaVersion: Int
    var endpointTargets: [String]
    var sessionID: String
    var oneTimePasscode: String
    var suggestedUSBPort: Int? = nil
    var strictSecurityEnabled = false

    var endpointTarget: String {
        guard let target = endpointTargets.first else {
            preconditionFailure("Pairing payload must include at least one endpoint target.")
        }
        return target
    }

    var bootstrapURLs: [URL] {
        let urls = endpointTargets.compactMap(Self.bootstrapURL(for:))
        guard urls.count == endpointTargets.count, !urls.isEmpty else {
            preconditionFailure("Invalid pairing endpoint targets: \(endpointTargets)")
        }
        return urls
    }

    var bootstrapURL: URL {
        guard let url = bootstrapURLs.first else {
            preconditionFailure("Pairing payload must include at least one bootstrap URL.")
        }
        return url
    }

    static let demo = PairingQRCodePayload(
        schemaVersion: 2,
        endpointTargets: ["127.0.0.1:38933"],
        sessionID: "pairing-demo-001",
        oneTimePasscode: "482913",
        suggestedUSBPort: 50211
    )

    static var demoScanValue: String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "dl.boldman.net"
        var queryItems = [
            URLQueryItem(name: "v", value: String(demo.schemaVersion)),
            URLQueryItem(name: "ept", value: demo.endpointTargets.joined(separator: ",")),
            URLQueryItem(name: "sid", value: demo.sessionID),
        ]
        if let suggestedUSBPort = demo.suggestedUSBPort {
            queryItems.append(URLQueryItem(name: "usp", value: String(suggestedUSBPort)))
        }
        if demo.strictSecurityEnabled {
            queryItems.append(URLQueryItem(name: "sec", value: "1"))
        }
        components.queryItems = queryItems
        components.fragment = "opt=\(demo.oneTimePasscode)"
        return components.string ?? "https://dl.boldman.net"
    }

    static func bootstrapURL(for endpointTarget: String) -> URL? {
        guard !endpointTarget.contains("/"),
              !endpointTarget.contains("?"),
              !endpointTarget.contains("#"),
              var components = URLComponents(string: "http://\(endpointTarget)")
        else {
            return nil
        }

        guard components.host != nil, components.port != nil else {
            return nil
        }

        components.path = "/api/mobile/pairing/claim"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

enum InterruptionReason: String, Equatable, Sendable, Codable {
    case stoppedByUser
    case pausedBySystem
    case wifiLost
    case desktopUnreachable
    case reconnectRequired

    var title: String {
        switch self {
        case .stoppedByUser:
            return "Backup paused"
        case .pausedBySystem:
            return "Transfer Paused"
        case .wifiLost:
            return "Connection Lost"
        case .desktopUnreachable:
            return "Desktop Unreachable"
        case .reconnectRequired:
            return "Reconnect required"
        }
    }

    var message: String {
        switch self {
        case .stoppedByUser:
            return "No additional items will be sent. The desktop may continue indexing media that already arrived."
        case .pausedBySystem:
            return "The app was moved to the background. Return to AuBackup to continue."
        case .wifiLost:
            return "Wi-Fi disconnected. Your progress is saved — reconnect or plug in USB to continue."
        case .desktopUnreachable:
            return "The paired desktop is not reachable. Make sure it's on and running the app, then try again."
        case .reconnectRequired:
            return "Trust or session state expired. Resume from desktop so the session can be validated again."
        }
    }

    var systemImage: String {
        switch self {
        case .stoppedByUser:
            return "pause.circle.fill"
        case .pausedBySystem:
            return "moon.circle.fill"
        case .wifiLost:
            return "wifi.exclamationmark"
        case .desktopUnreachable:
            return "desktopcomputer.trianglebadge.exclamationmark"
        case .reconnectRequired:
            return "link.badge.plus"
        }
    }
}

struct HomeSummary: Equatable, Sendable, Codable {
    var desktopName: String?
    var lastBackupDescription: String?
    var permissionScope: PermissionScope
    var interruptionWarning: String? = nil

    static let firstLaunch = HomeSummary(
        desktopName: nil,
        lastBackupDescription: nil,
        permissionScope: .full,
        interruptionWarning: nil
    )
}

struct PermissionSummary: Equatable, Sendable, Codable {
    var mediaScope: PermissionScope
    var lowBatteryWarningNeeded: Bool
    var isCharging: Bool

    static let demo = PermissionSummary(
        mediaScope: .limited,
        lowBatteryWarningNeeded: true,
        isCharging: false
    )

    static let allClear = PermissionSummary(
        mediaScope: .full,
        lowBatteryWarningNeeded: false,
        isCharging: true
    )
}

enum TransferPhase: String, Equatable, Sendable, Codable {
    case preparing
    case transferring
    case stopped
    case completed
    case failed
}

struct TransferSnapshot: Equatable, Sendable, Codable {
    var transferredCount: Int
    var totalCount: Int
    var failedCount: Int
    var skippedCount: Int = 0
    var transport: TransferTransport
    var liveTransports: [TransferTransport]? = nil
    var transferSpeedBytesPerSecond: Double? = nil
    var etaMinutes: Double?
    var phase: TransferPhase
    var failureMessage: String? = nil

    var activeTransportsForDisplay: [TransferTransport] {
        let candidates = (liveTransports?.isEmpty == false) ? (liveTransports ?? []) : [transport]
        var uniqueTransports: [TransferTransport] = []
        var seenTransports = Set<TransferTransport>()
        for transport in candidates {
            if seenTransports.insert(transport).inserted {
                uniqueTransports.append(transport)
            }
        }
        return uniqueTransports.isEmpty ? [transport] : uniqueTransports
    }

    var progress: Double {
        guard totalCount > 0 else {
            return 0
        }
        return Double(transferredCount) / Double(totalCount)
    }

    static func empty(
        transport: TransferTransport = .lan,
        phase: TransferPhase = .preparing
    ) -> TransferSnapshot {
        TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: transport,
            etaMinutes: nil,
            phase: phase
        )
    }

    static let demo = TransferSnapshot(
        transferredCount: 248,
        totalCount: 930,
        failedCount: 3,
        skippedCount: 17,
        transport: .lan,
        transferSpeedBytesPerSecond: 4.8 * 1_048_576.0,
        etaMinutes: 17,
        phase: .transferring,
        failureMessage: nil
    )
}

extension TransferSnapshot {
    enum CodingKeys: String, CodingKey {
        case transferredCount
        case totalCount
        case failedCount
        case skippedCount
        case transport
        case liveTransports
        case transferSpeedBytesPerSecond
        case legacyTransferSpeedText
        case etaMinutes
        case phase
        case failureMessage
        case legacyStatusMessage = "statusMessage"
        case legacyGuidanceMessage = "guidanceMessage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transferredCount = try container.decode(Int.self, forKey: .transferredCount)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        failedCount = try container.decode(Int.self, forKey: .failedCount)
        skippedCount = try container.decodeIfPresent(Int.self, forKey: .skippedCount) ?? 0
        transport = try container.decode(TransferTransport.self, forKey: .transport)
        liveTransports = try container.decodeIfPresent([TransferTransport].self, forKey: .liveTransports)
        transferSpeedBytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .transferSpeedBytesPerSecond)
        etaMinutes = try container.decodeIfPresent(Double.self, forKey: .etaMinutes)

        if let decodedPhase = try container.decodeIfPresent(TransferPhase.self, forKey: .phase) {
            phase = decodedPhase
        } else {
            let legacyStatusMessage = try container.decodeIfPresent(String.self, forKey: .legacyStatusMessage) ?? ""
            let normalizedLegacyStatusMessage = legacyStatusMessage.lowercased()
            if normalizedLegacyStatusMessage.contains("stopped") {
                phase = .stopped
            } else if normalizedLegacyStatusMessage.contains("complete") || normalizedLegacyStatusMessage.contains("finished") {
                phase = .completed
            } else if failedCount > 0 && totalCount == 0 {
                phase = .failed
            } else if totalCount == 0 && transferredCount == 0 {
                phase = .preparing
            } else {
                phase = .transferring
            }
        }

        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
        if failureMessage == nil {
            let legacyStatusMessage = try container.decodeIfPresent(String.self, forKey: .legacyStatusMessage)
            if phase == .failed, let legacyStatusMessage, !legacyStatusMessage.isEmpty {
                failureMessage = legacyStatusMessage
            }
        }

        if transferSpeedBytesPerSecond == nil,
           let legacyTransferSpeedText = try container.decodeIfPresent(String.self, forKey: .legacyTransferSpeedText) {
            transferSpeedBytesPerSecond = Self.transferSpeedBytesPerSecond(from: legacyTransferSpeedText)
        }
        _ = try container.decodeIfPresent(String.self, forKey: .legacyGuidanceMessage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transferredCount, forKey: .transferredCount)
        try container.encode(totalCount, forKey: .totalCount)
        try container.encode(failedCount, forKey: .failedCount)
        try container.encode(skippedCount, forKey: .skippedCount)
        try container.encode(transport, forKey: .transport)
        try container.encodeIfPresent(liveTransports, forKey: .liveTransports)
        try container.encodeIfPresent(transferSpeedBytesPerSecond, forKey: .transferSpeedBytesPerSecond)
        try container.encodeIfPresent(etaMinutes, forKey: .etaMinutes)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
    }

    private static func transferSpeedBytesPerSecond(from legacyText: String) -> Double? {
        let normalizedText = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let megabytesPerSecondText = normalizedText
            .replacingOccurrences(of: "MB/s", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let megabytesPerSecond = Double(megabytesPerSecondText) else {
            return nil
        }
        return megabytesPerSecond * 1_048_576.0
    }
}

struct CompletionSummary: Equatable, Sendable, Codable {
    var title: String
    var message: String
    var itemsBackedUp: Int? = nil
    var durationDescription: String? = nil

    static let demo = CompletionSummary(
        title: "Backup Complete!",
        message: "Desktop confirmed this mobile backup session is complete. Already transferred items may still be finishing desktop indexing."
    )
}

func normalizedDesktopDisplayName(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return nil
    }
    guard trimmedValue.lowercased().hasSuffix(".local"), trimmedValue.count > 6 else {
        return trimmedValue
    }
    return String(trimmedValue.dropLast(6))
}
