import Foundation

enum AppRoute: String, Equatable, Sendable {
    case home
    case scanAndPair
    case permissions
    case transfer
    case interrupted
    case completed
}

enum HomePrimaryAction: Equatable, Sendable, Codable {
    case scanDesktopQRCode
    case resumeBackup
    case backupPendingItems(Int)

    var title: String {
        switch self {
        case .scanDesktopQRCode:
            return "Scan Desktop QR"
        case .resumeBackup:
            return "Resume Backup"
        case .backupPendingItems(let count):
            return "Back Up \(count) New Items"
        }
    }

    var systemImage: String {
        switch self {
        case .scanDesktopQRCode:
            return "qrcode.viewfinder"
        case .resumeBackup:
            return "arrow.clockwise.circle.fill"
        case .backupPendingItems:
            return "arrow.up.circle.fill"
        }
    }

    var showsSecondaryScanAction: Bool {
        switch self {
        case .scanDesktopQRCode:
            return false
        case .resumeBackup, .backupPendingItems:
            return true
        }
    }

    var isResumeAction: Bool {
        if case .resumeBackup = self {
            return true
        }
        return false
    }
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
            return "Only the items currently granted by iOS will be backed up."
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

enum TransferTransport: String, Equatable, Sendable, Codable {
    case lan
    case usb

    var title: String {
        switch self {
        case .lan:
            return "Wi-Fi LAN"
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
    var desktopName: String?
    var sessionID: String?
    var transport: TransferTransport?
    var message: String

    static let idle = PairingStatus(
        phase: .instructions,
        desktopName: nil,
        sessionID: nil,
        transport: nil,
        message: "Scan or paste the pairing link shown by the desktop app to begin secure local pairing. Camera permission should only be requested when the live scanner opens."
    )
}

struct PairingQRCodePayload: Codable, Equatable, Sendable {
    static let maxEndpointTargets = 5

    var schemaVersion: Int
    var endpointTargets: [String]
    var sessionID: String
    var oneTimePasscode: String

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
        schemaVersion: 1,
        endpointTargets: ["127.0.0.1:38933"],
        sessionID: "pairing-demo-001",
        oneTimePasscode: "482913"
    )

    static var demoScanValue: String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "dl.boldman.net"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(demo.schemaVersion)),
            URLQueryItem(name: "ept", value: demo.endpointTargets.joined(separator: ",")),
            URLQueryItem(name: "sid", value: demo.sessionID),
            URLQueryItem(name: "opt", value: demo.oneTimePasscode),
        ]
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
            return "Backup paused by iOS"
        case .wifiLost:
            return "Wi-Fi connection lost"
        case .desktopUnreachable:
            return "Desktop unavailable"
        case .reconnectRequired:
            return "Reconnect required"
        }
    }

    var message: String {
        switch self {
        case .stoppedByUser:
            return "No additional items will be sent. The desktop may continue indexing media that already arrived."
        case .pausedBySystem:
            return "The app was backgrounded or suspended. Resume when the device and desktop are ready again."
        case .wifiLost:
            return "The local network path dropped during transfer. Resume when both devices are reachable again."
        case .desktopUnreachable:
            return "The paired desktop could not be reached. You may need to resume from the desktop-driven flow."
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
    var primaryAction: HomePrimaryAction
    var permissionScope: PermissionScope
    var detailMessage: String

    static let firstLaunch = HomeSummary(
        desktopName: nil,
        pendingItemCount: nil,
        lastBackupDescription: nil,
        primaryAction: .scanDesktopQRCode,
        permissionScope: .full,
        detailMessage: "Back up the full eligible local iPhone library to the desktop app. No account or cloud relay is required, and notification permission is requested only when backup is about to start."
    )

    static func resumable(
        desktopName: String?,
        remainingItems: Int,
        permissionScope: PermissionScope
    ) -> HomeSummary {
        HomeSummary(
            desktopName: desktopName,
            pendingItemCount: remainingItems,
            lastBackupDescription: "The last backup did not finish.",
            primaryAction: .resumeBackup,
            permissionScope: permissionScope,
            detailMessage: "Resume the last session when the desktop is reachable again. Only new or unfinished work should continue."
        )
    }

    static func completed(
        desktopName: String?,
        permissionScope: PermissionScope,
        lastBackupDescription: String
    ) -> HomeSummary {
        HomeSummary(
            desktopName: desktopName,
            pendingItemCount: 0,
            lastBackupDescription: lastBackupDescription,
            primaryAction: .scanDesktopQRCode,
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
    var etaDescription: String?
    var statusMessage: String
    var guidanceMessage: String
    var isIncompleteLibrary: Bool

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
        etaDescription: "17 min remaining",
        statusMessage: "Backing up local photos and videos to the paired desktop.",
        guidanceMessage: "USB is generally faster and more stable than Wi-Fi LAN. Once desktop support lands, the app should prefer USB when it is available.",
        isIncompleteLibrary: true
    )
}

struct CompletionSummary: Equatable, Sendable, Codable {
    var title: String
    var message: String

    static let demo = CompletionSummary(
        title: "Backup complete",
        message: "Desktop confirmed this mobile backup session is complete. Already transferred items may still be finishing desktop indexing."
    )
}

struct LaunchSnapshot: Equatable, Sendable, Codable {
    var homeSummary: HomeSummary
    var permissionSummary: PermissionSummary
    var pairingStatus: PairingStatus
    var transferSnapshot: TransferSnapshot
    var lastInterruptionReason: InterruptionReason?

    static let firstLaunch = LaunchSnapshot(
        homeSummary: .firstLaunch,
        permissionSummary: .demo,
        pairingStatus: .idle,
        transferSnapshot: .demo,
        lastInterruptionReason: nil
    )

    static let resumable = LaunchSnapshot(
        homeSummary: .resumable(
            desktopName: "Studio Mac",
            remainingItems: 682,
            permissionScope: .limited
        ),
        permissionSummary: .demo,
        pairingStatus: .idle,
        transferSnapshot: .demo,
        lastInterruptionReason: .desktopUnreachable
    )
}
