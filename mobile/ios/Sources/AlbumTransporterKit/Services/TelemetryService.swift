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
    let backupFlowState: MobileBackupFlowState
    let backupSession: BackupSession?

    static let empty = TelemetryContext(
        route: .home,
        backupFlowState: .pendingPairing,
        backupSession: nil
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
    private let transportResolver: AppTransferTransportResolving
    private let telemetryClient: TelemetryClient
    private let contextProvider: TelemetryContextProvider

    init(
        transferService: TransferService,
        transportResolver: AppTransferTransportResolving,
        telemetryClient: TelemetryClient,
        contextProvider: TelemetryContextProvider
    ) {
        self.transferService = transferService
        self.transportResolver = transportResolver
        self.telemetryClient = telemetryClient
        self.contextProvider = contextProvider
    }

    func recordTelemetry(
        _ event: MobileTelemetryEvent,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let transferService = transferService
        let transportResolver = transportResolver
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = await mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot,
                transportResolver: transportResolver
            )
            await telemetryClient.record(event: event, attributes: mergedAttributes)
        }
    }

    func beginTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let transferService = transferService
        let transportResolver = transportResolver
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = await mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot,
                transportResolver: transportResolver
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
        let transportResolver = transportResolver
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = await mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot,
                transportResolver: transportResolver
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
        let transportResolver = transportResolver
        let telemetryClient = telemetryClient
        let context = contextProvider.currentContext()
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = await mergedTelemetryAttributes(
                extraAttributes: attributes,
                context: context,
                transferSnapshot: transferSnapshot,
                transportResolver: transportResolver
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
        transferSnapshot: TransferSnapshot,
        transportResolver: AppTransferTransportResolving
    ) async -> MobileTelemetryAttributes {
        var attributes: MobileTelemetryAttributes = [
            "app.route": .string(routeName(context.route)),
            "backup.flow_state": .string(context.backupFlowState.rawValue),
            "app.has_paired_desktop": .bool(context.backupSession?.desktopName?.isEmpty == false),
            "transfer.transferred_count": .int(transferSnapshot.transferredCount),
            "transfer.total_count": .int(transferSnapshot.totalCount),
            "transfer.failed_count": .int(transferSnapshot.failedCount)
        ]
        if let transport = await transportResolver.currentTransport()
            ?? transferSnapshot.activeTransportsForDisplay.first {
            attributes["transfer.transport"] = .string(transport.rawValue)
        }
        if let sessionID = context.backupSession?.sessionID,
           !sessionID.isEmpty {
            attributes["correlation.session_id"] = .string(sessionID)
        }
        if let backupSession = context.backupSession {
            attributes["backup.session_status"] = .string(backupSession.status.rawValue)
        }
        if let desktopName = context.backupSession?.desktopName, !desktopName.isEmpty {
            attributes["pairing.desktop_name_present"] = .bool(true)
            attributes["pairing.desktop_name_length"] = .int(desktopName.count)
        }
        return attributes
    }

    private func mergedTelemetryAttributes(
        extraAttributes: MobileTelemetryAttributes,
        context: TelemetryContext,
        transferSnapshot: TransferSnapshot,
        transportResolver: AppTransferTransportResolving
    ) async -> MobileTelemetryAttributes {
        var merged = await telemetryContextAttributes(
            context: context,
            transferSnapshot: transferSnapshot,
            transportResolver: transportResolver
        )
        for (key, value) in extraAttributes {
            merged[key] = value
        }
        return merged
    }

    private func routeName(_ route: AppRoute) -> String {
        switch route {
        case .home:
            return "home"
        case .scan:
            return "scan"
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
