import Foundation

enum AppRoute: String, Equatable, Sendable {
    case home
    case scan
    case pair
    case permissions
    case transfer
    case completed
    case error
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
    case photosOnly
    case videosOnly
    case denied

    var title: String {
        switch self {
        case .full:
            return "Full Library Access"
        case .limited:
            return "Limited Library Access"
        case .photosOnly:
            return "Photos Only"
        case .videosOnly:
            return "Videos Only"
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
        case .photosOnly:
            return "Videos are excluded until video access is granted."
        case .videosOnly:
            return "Photos are excluded until photo access is granted."
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

enum PairingPhase: String, Equatable, Sendable, Codable {
    case instructions
    case scanning
    case pairing
    case paired
    case expired
    case failed
}

struct PairingStatus: Equatable, Sendable, Codable {
    var phase: PairingPhase
    var backupFlowState: MobileBackupFlowState
    var desktopName: String?
    var sessionID: String?
    var transport: TransferTransport?
    var message: String

    enum CodingKeys: String, CodingKey {
        case phase
        case backupFlowState
        case desktopName
        case sessionID
        case transport
        case message
    }

    init(
        phase: PairingPhase,
        backupFlowState: MobileBackupFlowState = .pendingPairing,
        desktopName: String?,
        sessionID: String?,
        transport: TransferTransport?,
        message: String
    ) {
        self.phase = phase
        self.backupFlowState = backupFlowState
        self.desktopName = desktopName
        self.sessionID = sessionID
        self.transport = transport
        self.message = message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(PairingPhase.self, forKey: .phase)
        backupFlowState = try container.decodeIfPresent(MobileBackupFlowState.self, forKey: .backupFlowState) ?? .pendingPairing
        desktopName = try container.decodeIfPresent(String.self, forKey: .desktopName)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        transport = try container.decodeIfPresent(TransferTransport.self, forKey: .transport)
        message = try container.decode(String.self, forKey: .message)
    }

    static let idle = PairingStatus(
        phase: .instructions,
        backupFlowState: .pendingPairing,
        desktopName: nil,
        sessionID: nil,
        transport: nil,
        message: "Scan the desktop QR code to begin secure local pairing."
    )
}

struct PairingQRCodePayload: Codable, Equatable, Sendable {
    static let maxEndpointTargets = 5

    var schemaVersion: Int
    var endpointTargets: [String]
    var sessionID: String
    var oneTimePasscode: String
    var suggestedUSBPort: Int? = nil

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
            URLQueryItem(name: "opt", value: demo.oneTimePasscode),
        ]
        if let suggestedUSBPort = demo.suggestedUSBPort {
            queryItems.append(URLQueryItem(name: "usp", value: String(suggestedUSBPort)))
        }
        components.queryItems = queryItems
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
    var pendingItemCount: Int?
    var lastBackupDescription: String?
    var permissionScope: PermissionScope
    var detailMessage: String
    var previouslyTransferredDescription: String? = nil
    var interruptionWarning: String? = nil

    static let firstLaunch = HomeSummary(
        desktopName: nil,
        pendingItemCount: nil,
        lastBackupDescription: nil,
        permissionScope: .full,
        detailMessage: "Back up the full eligible local iPhone library to the desktop app. No account or cloud relay is required, and notification permission is requested only when backup is about to start."
    )

    static func completed(
        desktopName: String?,
        permissionScope: PermissionScope,
        lastBackupDescription: String
    ) -> HomeSummary {
        HomeSummary(
            desktopName: desktopName,
            pendingItemCount: 0,
            lastBackupDescription: lastBackupDescription,
            permissionScope: permissionScope,
            detailMessage: "Your full eligible library is up to date for the last confirmed session. Scan again when you are ready to pair with the desktop."
        )
    }
}

struct PermissionSummary: Equatable, Sendable, Codable {
    var cameraGranted: Bool
    var notificationsGranted: Bool
    var mediaScope: PermissionScope
    var excludedCategoryDescription: String?
    var lowBatteryWarningNeeded: Bool
    var isCharging: Bool

    static let demo = PermissionSummary(
        cameraGranted: true,
        notificationsGranted: false,
        mediaScope: .limited,
        excludedCategoryDescription: "Only the subset currently granted by iOS will be included in this backup.",
        lowBatteryWarningNeeded: true,
        isCharging: false
    )

    static let allClear = PermissionSummary(
        cameraGranted: true,
        notificationsGranted: true,
        mediaScope: .full,
        excludedCategoryDescription: nil,
        lowBatteryWarningNeeded: false,
        isCharging: true
    )
}

struct TransferSnapshot: Equatable, Sendable, Codable {
    var transferredCount: Int
    var totalCount: Int
    var failedCount: Int
    var transport: TransferTransport
    var liveTransports: [TransferTransport]? = nil
    var transferSpeedText: String? = nil
    var etaDescription: String?
    var statusMessage: String
    var guidanceMessage: String
    var isIncompleteLibrary: Bool

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

    static let demo = TransferSnapshot(
        transferredCount: 248,
        totalCount: 930,
        failedCount: 3,
        transport: .lan,
        transferSpeedText: "4.80 MB/s",
        etaDescription: "17 min remaining",
        statusMessage: "Backing up local photos and videos to the paired desktop.",
        guidanceMessage: "USB is generally faster and more stable than Wi-Fi. Once desktop support lands, the app should prefer USB when it is available.",
        isIncompleteLibrary: true
    )
}

struct CompletionSummary: Equatable, Sendable, Codable {
    var title: String
    var message: String
    var itemsBackedUp: Int? = nil
    var totalTransferredDescription: String? = nil
    var durationDescription: String? = nil
    var completedAtDescription: String? = nil

    static let demo = CompletionSummary(
        title: "Backup Complete!",
        message: "Desktop confirmed this mobile backup session is complete. Already transferred items may still be finishing desktop indexing."
    )
}

struct LaunchSnapshot: Equatable, Sendable, Codable {
    var homeSummary: HomeSummary
    var permissionSummary: PermissionSummary
    var pairingStatus: PairingStatus
    var transferSnapshot: TransferSnapshot
    var removeAfterBackupEnabled: Bool

    init(
        homeSummary: HomeSummary,
        permissionSummary: PermissionSummary,
        pairingStatus: PairingStatus,
        transferSnapshot: TransferSnapshot,
        removeAfterBackupEnabled: Bool = false
    ) {
        self.homeSummary = homeSummary
        self.permissionSummary = permissionSummary
        self.pairingStatus = pairingStatus
        self.transferSnapshot = transferSnapshot
        self.removeAfterBackupEnabled = removeAfterBackupEnabled
    }

    enum CodingKeys: String, CodingKey {
        case homeSummary
        case permissionSummary
        case pairingStatus
        case transferSnapshot
        case removeAfterBackupEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeSummary = try container.decode(HomeSummary.self, forKey: .homeSummary)
        permissionSummary = try container.decode(PermissionSummary.self, forKey: .permissionSummary)
        pairingStatus = try container.decode(PairingStatus.self, forKey: .pairingStatus)
        transferSnapshot = try container.decode(TransferSnapshot.self, forKey: .transferSnapshot)
        removeAfterBackupEnabled = try container.decodeIfPresent(Bool.self, forKey: .removeAfterBackupEnabled) ?? false
    }

    static let firstLaunch = LaunchSnapshot(
        homeSummary: .firstLaunch,
        permissionSummary: .demo,
        pairingStatus: .idle,
        transferSnapshot: .demo,
        removeAfterBackupEnabled: false
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
