import Foundation

@MainActor
protocol TelemetryService {
    func recordTelemetry(
        _ event: MobileTelemetryEvent,
        attributes: MobileTelemetryAttributes
    )
    func beginTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes
    )
    func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    )
    func incrementTelemetryMetric(
        _ metric: MobileTelemetryMetric,
        by value: Int,
        attributes: MobileTelemetryAttributes
    )
    func beginBackupSessionTelemetry()
    func recordDialogView(name: String)
    func recordInteraction(name: String, location: String)
    func forceFlush()
}

@MainActor
protocol TelemetryContextProvider {
    func currentContext() -> TelemetryContext
    func updateContext(_ context: TelemetryContext)
}

struct TelemetryContext {
    let route: AppRoute
    let homeSummary: HomeSummary
    let pairingStatus: PairingStatus
    let permissionSummary: PermissionSummary

    static let empty = TelemetryContext(
        route: .home,
        homeSummary: .firstLaunch,
        pairingStatus: .idle,
        permissionSummary: .demo
    )
}

@MainActor
final class DefaultTelemetryContextProvider: TelemetryContextProvider {
    private var context: TelemetryContext = .empty

    func currentContext() -> TelemetryContext {
        context
    }

    func updateContext(_ context: TelemetryContext) {
        self.context = context
    }
}

@MainActor
final class DefaultTelemetryService: TelemetryService {
    private let transferService: TransferService
    private let telemetryClient: TelemetryClient
    private let contextProvider: TelemetryContextProvider

    init(
        transferService: TransferService,
        telemetryClient: TelemetryClient,
        contextProvider: TelemetryContextProvider
    ) {
        self.transferService = transferService
        self.telemetryClient = telemetryClient
        self.contextProvider = contextProvider
    }

    func recordTelemetry(
        _ event: MobileTelemetryEvent,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let transferService = transferService
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot
            )
            await telemetryClient.record(event: event, attributes: mergedAttributes)
        }
    }

    func beginTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let transferService = transferService
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot
            )
            await telemetryClient.begin(span: span, attributes: mergedAttributes)
        }
    }

    func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:],
        status: MobileTelemetrySpanStatus? = nil
    ) {
        let transferService = transferService
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot
            )
            await telemetryClient.end(span: span, attributes: mergedAttributes, status: status)
        }
    }

    func incrementTelemetryMetric(
        _ metric: MobileTelemetryMetric,
        by value: Int = 1,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let transferService = transferService
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot
            )
            await telemetryClient.increment(metric: metric, by: value, attributes: mergedAttributes)
        }
    }

    func beginBackupSessionTelemetry() {
        beginTelemetrySpan(.backupSession)
        incrementTelemetryMetric(.backupAttempts)
    }

    func recordDialogView(name: String) {
        recordTelemetry(
            .dialogViewed,
            attributes: [
                "ui.view.kind": .string("dialog"),
                "ui.view.name": .string(name)
            ]
        )
    }

    func recordInteraction(name: String, location: String) {
        recordTelemetry(
            .interactionTriggered,
            attributes: [
                "ui.interaction.name": .string(name),
                "ui.interaction.location": .string(location)
            ]
        )
    }

    func forceFlush() {
        let telemetryClient = telemetryClient
        Task.detached(priority: .utility) {
            await telemetryClient.forceFlush()
        }
    }

    private func telemetryContextAttributes(
        context: TelemetryContext,
        transferSnapshot: TransferSnapshot
    ) -> MobileTelemetryAttributes {
        var attributes: MobileTelemetryAttributes = [
            "app.route": .string(context.route.rawValue),
            "backup.flow_state": .string(context.pairingStatus.backupFlowState.rawValue),
            "pairing.phase": .string(context.pairingStatus.phase.rawValue),
            "permission.media_scope": .string(context.permissionSummary.mediaScope.rawValue),
            "permission.camera_granted": .bool(context.permissionSummary.cameraGranted),
            "permission.notifications_granted": .bool(context.permissionSummary.notificationsGranted),
            "permission.low_battery_warning_needed": .bool(context.permissionSummary.lowBatteryWarningNeeded),
            "permission.is_charging": .bool(context.permissionSummary.isCharging),
            "app.has_paired_desktop": .bool(context.pairingStatus.desktopName?.isEmpty == false),
            "transfer.transferred_count": .int(transferSnapshot.transferredCount),
            "transfer.total_count": .int(transferSnapshot.totalCount),
            "transfer.failed_count": .int(transferSnapshot.failedCount)
        ]
        if let transport = context.pairingStatus.transport ?? transferSnapshot.activeTransportsForDisplay.first {
            attributes["transfer.transport"] = .string(transport.rawValue)
        }
        if let sessionID = context.pairingStatus.sessionID, !sessionID.isEmpty {
            attributes["correlation.session_id"] = .string(sessionID)
        }
        if let pendingItemCount = context.homeSummary.pendingItemCount {
            attributes["home.pending_item_count"] = .int(pendingItemCount)
        }
        if let desktopName = context.pairingStatus.desktopName, !desktopName.isEmpty {
            attributes["pairing.desktop_name_present"] = .bool(true)
            attributes["pairing.desktop_name_length"] = .int(desktopName.count)
        }
        return attributes
    }

    private func mergedTelemetryAttributes(
        extraAttributes: MobileTelemetryAttributes,
        context: TelemetryContext,
        transferSnapshot: TransferSnapshot
    ) -> MobileTelemetryAttributes {
        var merged = telemetryContextAttributes(
            context: context,
            transferSnapshot: transferSnapshot
        )
        for (key, value) in extraAttributes {
            merged[key] = value
        }
        return merged
    }
}
