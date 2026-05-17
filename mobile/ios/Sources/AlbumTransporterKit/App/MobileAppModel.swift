import Foundation
import UIKit
import Combine

@MainActor
final class MobileAppModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home {
        didSet { pushTelemetryContext() }
    }
    @Published private(set) var pairingStatus = PairingStatus.idle {
        didSet { pushTelemetryContext() }
    }
    @Published private(set) var errorSummary = ErrorSummary.generic

    @Published var isShowingIncomingLinkReplacementConfirmation = false

    private var hasLoaded = false
    private var pendingIncomingUniversalLinkPayload: String?
    private var isProcessingIncomingUniversalLink = false
    private let universalLinkHost = "dl.boldman.net"
    let backupSessionProvider: BackupSessionProviding
    private let qrCodePayloadDecoder: QRCodePayloadDecoding
    let pairingService: PairingService
    let permissionService: PermissionService
    let transferService: TransferService
    private let telemetryContextProvider: TelemetryContextProvider
    private let telemetryService: TelemetryService
    private var backupFlowStateMachine = MobileBackupFlowStateMachine()
    private var memoryWarningObservationTask: Task<Void, Never>?
    private var appLifecycleObservationTask: Task<Void, Never>?
    private var backupSessionObserver: AnyCancellable?

    init(
        backupSessionProvider: BackupSessionProviding,
        qrCodePayloadDecoder: QRCodePayloadDecoding,
        pairingService: PairingService,
        permissionService: PermissionService,
        transferService: TransferService,
        telemetryService: TelemetryService,
        telemetryContextProvider: TelemetryContextProvider
    ) {
        self.backupSessionProvider = backupSessionProvider
        self.qrCodePayloadDecoder = qrCodePayloadDecoder
        self.pairingService = pairingService
        self.permissionService = permissionService
        self.transferService = transferService
        self.telemetryContextProvider = telemetryContextProvider
        self.telemetryService = telemetryService
        self.backupSessionObserver = backupSessionProvider.backupSessionPublisher
            .sink { [weak self] _ in
                self?.pushTelemetryContext()
            }
        pushTelemetryContext()
        configureMemoryWarningObservation()
        configureAppLifecycleObservation()
    }

    deinit {
        memoryWarningObservationTask?.cancel()
        appLifecycleObservationTask?.cancel()
    }
    
    func onHomeCompleted(with result: HomePageResult) async {
        switch result.result {
        case .success:
            await openScanFlow()
        case .failure:
            break
        }
    }

    func onScanningCompleted(with result: ScanningPageResult) async {
        switch result.result {
        case .success(let qrString):
            await showPairingPage(qrString: qrString)
        case .failure(.scannerFailed):
            presentErrorSummary(
                title: "Scanner failed",
                message: "The camera scanner couldn't continue. Restart the backup session or return home."
            )
        case .failure:
            presentErrorSummary(
                title: "Scanner error",
                message: "An unexpected error occurred. Restart the backup session or return home."
            )
        }
    }

    func onPairingCompleted(with result: PairingPageResult) async {
        // Update pairing status with the result from the view model
        if let resultStatus = result.pairingStatus {
            pairingStatus = resultStatus
            applyPairingStatusStateTransition(resultStatus)
        }
        
        switch result.result {
        case .success:
            guard pairingStatus.backupFlowState == .pairingCompleted else {
                reportPairingFailure(
                    reason: "pairing_success_without_completion_state",
                    pairingAttributes: [
                        "pairing.backup_flow_state": .string(pairingStatus.backupFlowState.rawValue)
                    ]
                )
                return
            }

            // Pairing succeeded - save session and navigate to permissions
            await backupSessionProvider.saveBackupSession(
                status: .paired,
                sessionID: pairingStatus.sessionID,
                desktopName: pairingStatus.desktopName
            )
            route = .permissions
            recordTelemetry(.pairingSucceeded)
            endTelemetrySpan(.pairingFlow, status: .ok)

        case .failure(.cancelled):
            // User cancelled pairing - return home
            await returnHome()
            
        case .failure(let error):
            // Check if desktop stopped pairing
            if pairingStatus.backupFlowState == .pairingStopped {
                route = .home
                reportPairingFailure(reason: "desktop_stopped_pairing")
                endTelemetrySpan(
                    .backupSession,
                    attributes: [
                        "backup.failure_reason": .string("desktop_stopped_pairing")
                    ],
                    status: .error("desktop_stopped_pairing")
                )
                await backupSessionProvider.saveBackupSession(
                    status: .failed,
                    sessionID: pairingStatus.sessionID,
                    desktopName: pairingStatus.desktopName
                )
                return
            }
            
            // Pairing failed (invalid QR or other error) - show error page
            reportPairingFailure(
                reason: error.title,
                pairingAttributes: [
                    "pairing.failure_message": .string(error.message)
                ]
            )
            presentErrorSummary(
                title: error.title,
                message: error.message
            )
        }
    }

    func onPermissionsCompleted(with result: PermissionsPageResult) async {
        switch result.result {
        case .success:
            await triggerTransfer()
        case .failure(.lowBatteryDeclined):
            await abortPreflightAndReturnHome(reason: "low_battery_declined")
        case .failure(.permissionsCancelled):
            await abortPreflightAndReturnHome(reason: "permissions_cancelled")
        case .failure(.preflightFailed), .failure(.unknown):
            presentErrorSummary(
                title: "Preflight failed",
                message: "AuBackup couldn't complete backup preflight. Restart the backup session or return home."
            )
        }
    }

    func onTransferCompleted(with result: TransferPageResult) async {
        switch result.result {
        case .success:
            await finalizeCompletedTransfer()
        case .failure(.stopConfirmed):
            await finalizeStoppedTransfer()
        case .failure(.transferFailed), .failure(.unknown):
            presentErrorSummary(
                title: "Transfer failed",
                message: "AuBackup couldn't continue this transfer. Restart the backup session or return home."
            )
        }
    }

    func onCompletionCompleted(with result: CompletionPageResult) async {
        switch result.result {
        case .success:
            await returnHome()
        case .failure:
            presentErrorSummary(
                title: "Completion failed",
                message: "AuBackup couldn't finish this completion step. Restart the backup session or return home."
            )
        }
    }

    func onErrorCompleted(with result: ErrorPageResult) async {
        switch result.result {
        case .success:
            await openScanFlow()
        case .failure:
            await returnHome()
        }
    }

    var navigationTitle: String {
        switch route {
        case .home:
            return "AuBackup"
        case .scan:
            return "Scan QR"
        case .pair:
            return "Pairing"
        case .permissions:
            return "Permissions"
        case .transfer:
            return "Backup in Progress"
        case .completed:
            return "Backup Complete"
        case .error:
            return "Backup Error"
        }
    }

    var routeName: String {
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

    func load() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await backupSessionProvider.load()
        await permissionService.setRemoveAfterBackupEnabled(false)
        let persistedBackupSession = backupSessionProvider.backupSession
        if let persistedBackupSession {
            pairingStatus = pairingStatus(for: persistedBackupSession)
            backupFlowStateMachine = MobileBackupFlowStateMachine(
                state: backupFlowState(for: persistedBackupSession.status)
            )
        } else {
            pairingStatus = .idle
            backupFlowStateMachine = MobileBackupFlowStateMachine()
        }
        route = .home
        await transferService.stageTransferCompletionState(nil)
        let pairingService = pairingService
        Task.detached(priority: .utility) {
            await pairingService.primeNetworkAccess()
        }
        recordTelemetry(.appLaunched)
    }

    func openScanFlow() async {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        errorSummary = .generic
        beginBackupSessionTelemetry()
        transitionBackupFlow(.pairingStarted)
        pairingStatus = PairingStatus(
            backupFlowState: .pendingPairing,
            desktopName: backupSessionProvider.backupSession?.desktopName,
            sessionID: nil,
            transport: nil
        )
        route = .scan
        recordTelemetry(.scanStarted)
    }

    func handleIncomingUniversalLink(_ url: URL) async {
        guard isSupportedUniversalLink(url) else {
            return
        }
        let payload = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return
        }

        if route == .transfer {
            pendingIncomingUniversalLinkPayload = payload
            isShowingIncomingLinkReplacementConfirmation = true
            return
        }

        await processIncomingUniversalLinkPayload(payload)
    }

    func confirmIncomingUniversalLinkReplacement() async {
        guard let payload = pendingIncomingUniversalLinkPayload else {
            isShowingIncomingLinkReplacementConfirmation = false
            return
        }
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        await stopTransferForIncomingLinkReplacementIfNeeded()
        await processIncomingUniversalLinkPayload(payload)
    }

    func cancelIncomingUniversalLinkReplacement() {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
    }

    func showPairingPage(qrString: String) async {
        beginTelemetrySpan(.pairingFlow)
        transitionBackupFlow(.pairingStarted)
        route = .pair(qrString: qrString)
        pairingStatus = PairingStatus(
            backupFlowState: .pendingPairing,
            desktopName: backupSessionProvider.backupSession?.desktopName,
            sessionID: nil,
            transport: nil
        )
        recordTelemetry(.pairingStarted)
    }

    private func abortPreflightAndReturnHome(reason: String) async {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        await permissionService.setRemoveAfterBackupEnabled(false)
        let interruptionSnapshot = preflightInterruptionSnapshot()
        await transferService.stageTransferSnapshot(interruptionSnapshot)
        await transferService.stageTransferCompletionState(nil)
        transitionBackupFlow(.transferStopped)
        route = .home
        let stopAttributes = transferStopTelemetryAttributes(reason: reason)
        let backupFailureAttributes = backupFailureTelemetryAttributes(reason: reason)
        recordTelemetry(.transferStopped, attributes: stopAttributes)
        incrementTelemetryMetric(.backupFailures, attributes: backupFailureAttributes)
        endTelemetrySpan(
            .backupPreflight,
            attributes: backupFailureAttributes,
            status: .error(reason)
        )
        endTelemetrySpan(
            .backupSession,
            attributes: backupFailureAttributes,
            status: .error(reason)
        )
        await backupSessionProvider.saveBackupSession(
            status: .stopped,
            sessionID: pairingStatus.sessionID,
            desktopName: pairingStatus.desktopName
        )
    }

    func requestStopTransfer() {
        recordTelemetry(.transferStopRequested)
    }

    private func finalizeStoppedTransfer() async {
        await finalizeStoppedTransfer(reason: "user_requested")
    }

    private func stopTransferForIncomingLinkReplacementIfNeeded() async {
        guard route == .transfer else {
            return
        }
        let snapshot = await currentTransferSnapshot()
        _ = await transferService.stopTransfer(current: snapshot)
        await transferService.stageTransferSnapshot(snapshot)
        await finalizeStoppedTransfer(reason: "replaced_by_universal_link")
    }

    private func finalizeStoppedTransfer(reason: String) async {
        await transferService.stageTransferCompletionState(nil)
        transitionBackupFlow(.transferStopped)
        route = .home

        let stopAttributes = transferStopTelemetryAttributes(reason: reason)
        let backupFailureAttributes = backupFailureTelemetryAttributes(reason: reason)
        recordTelemetry(.transferStopped, attributes: stopAttributes)
        incrementTelemetryMetric(.backupFailures, attributes: backupFailureAttributes)
        endTelemetrySpan(
            .transferFlow,
            attributes: stopAttributes,
            status: .error(reason)
        )
        endTelemetrySpan(
            .backupSession,
            attributes: backupFailureAttributes,
            status: .error(reason)
        )
        await backupSessionProvider.saveBackupSession(
            status: .stopped,
            sessionID: pairingStatus.sessionID,
            desktopName: pairingStatus.desktopName
        )
    }

    var backupFlowState: MobileBackupFlowState {
        backupFlowStateMachine.state
    }

    private func finalizeCompletedTransfer() async {
        let completionContext = await resolvedTransferCompletionContext()
        let snapshot = completionContext.snapshot
        let cleanupResult = completionContext.cleanupResult
        let sessionDuration = completionContext.sessionDuration
        transitionBackupFlow(snapshot.failedCount == 0 ? .transferCompleted : .transferFailed)
        route = .completed

        let isRemoveAfterBackupEnabled = await permissionService.removeAfterBackupEnabled()
        let completionAttributes = completionTelemetryAttributes(
            snapshot: snapshot,
            cleanupResult: cleanupResult,
            sessionDuration: sessionDuration,
            isRemoveAfterBackupEnabled: isRemoveAfterBackupEnabled
        )
        let completionStatus = transferCompletionSpanStatus(for: snapshot)
        recordTelemetry(.transferCompleted, attributes: completionAttributes)
        incrementTelemetryMetric(.backupSuccesses, attributes: completionAttributes)
        incrementTelemetryMetric(
            .backupCompletedItems,
            by: snapshot.transferredCount,
            attributes: completionAttributes
        )
        endTelemetrySpan(
            .transferFlow,
            attributes: completionAttributes,
            status: completionStatus
        )
        endTelemetrySpan(
            .backupSession,
            attributes: completionAttributes,
            status: completionStatus
        )
        await backupSessionProvider.saveBackupSession(
            status: snapshot.failedCount == 0 ? .completed : .failed,
            sessionID: pairingStatus.sessionID,
            desktopName: pairingStatus.desktopName
        )
    }

    func returnHome() async {
        await transferService.stageTransferCompletionState(nil)
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        await permissionService.setRemoveAfterBackupEnabled(false)
        errorSummary = .generic
        transitionBackupFlow(.resetToPendingPairing)
        route = .home
    }

    private func presentErrorSummary(title: String, message: String) {
        errorSummary = ErrorSummary(title: title, message: message)
        route = .error
    }

    private func isSupportedUniversalLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host == universalLinkHost
    }

    private func processIncomingUniversalLinkPayload(_ payload: String) async {
        guard !isProcessingIncomingUniversalLink else {
            return
        }
        isProcessingIncomingUniversalLink = true
        defer { isProcessingIncomingUniversalLink = false }

        await openScanFlow()
        await showPairingPage(qrString: payload)
    }

    private func triggerTransfer() async {
        transitionBackupFlow(.transferStarted)
        route = .transfer
        let isRemoveAfterBackupEnabled = await permissionService.removeAfterBackupEnabled()
        let isIncompleteLibrary = await permissionService.loadPermissionSummary().mediaScope != .full
        let initialSnapshot = initialTransferSnapshot()
        await transferService.stageTransferSnapshot(initialSnapshot)
        await transferService.stageTransferCompletionState(nil)
        endTelemetrySpan(.backupPreflight, status: .ok)
        beginTelemetrySpan(.transferFlow)
        recordTelemetry(.transferStarted, attributes: transferStartTelemetryAttributes(
            isRemoveAfterBackupEnabled: isRemoveAfterBackupEnabled,
            isIncompleteLibrary: isIncompleteLibrary
        ))
    }

    private func reportPairingFailure(
        reason: String,
        pairingAttributes: MobileTelemetryAttributes = [:]
    ) {
        var resolvedPairingAttributes = pairingAttributes
        resolvedPairingAttributes["pairing.failure_reason"] = .string(reason)

        recordTelemetry(.pairingFailed, attributes: resolvedPairingAttributes)
        incrementTelemetryMetric(
            .backupFailures,
            attributes: [
                "backup.failure_reason": .string(reason)
            ]
        )
        endTelemetrySpan(
            .pairingFlow,
            attributes: resolvedPairingAttributes,
            status: .error(reason)
        )
    }

    private func initialTransferSnapshot() -> TransferSnapshot {
        TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: pairingStatus.transport ?? .lan,
            etaMinutes: nil,
            phase: .preparing
        )
    }

    private func preflightInterruptionSnapshot() -> TransferSnapshot {
        TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: pairingStatus.transport ?? .lan,
            etaMinutes: nil,
            phase: .stopped
        )
    }

    private func transferStartTelemetryAttributes(
        isRemoveAfterBackupEnabled: Bool,
        isIncompleteLibrary: Bool
    ) -> MobileTelemetryAttributes {
        [
            "transfer.remove_after_backup_enabled": .bool(isRemoveAfterBackupEnabled),
            "transfer.is_incomplete_library": .bool(isIncompleteLibrary)
        ]
    }

    private func transferStopTelemetryAttributes(reason: String) -> MobileTelemetryAttributes {
        [
            "transfer.stop_reason": .string(reason)
        ]
    }

    private func backupFailureTelemetryAttributes(reason: String) -> MobileTelemetryAttributes {
        [
            "backup.failure_reason": .string(reason)
        ]
    }

    private func resolvedTransferCompletionContext() async -> (
        snapshot: TransferSnapshot,
        cleanupResult: TransferAssetCleanupResult,
        sessionDuration: TimeInterval?
    ) {
        if let completionState = await transferService.transferCompletionState() {
            return (
                snapshot: completionState.snapshot,
                cleanupResult: completionState.cleanupResult,
                sessionDuration: completionState.sessionDuration
            )
        }
        return (
            snapshot: await currentTransferSnapshot(),
            cleanupResult: .skipped,
            sessionDuration: nil
        )
    }

    private func completionTelemetryAttributes(
        snapshot: TransferSnapshot,
        cleanupResult: TransferAssetCleanupResult,
        sessionDuration: TimeInterval?,
        isRemoveAfterBackupEnabled: Bool
    ) -> MobileTelemetryAttributes {
        var attributes: MobileTelemetryAttributes = [
            "transfer.transferred_count": .int(snapshot.transferredCount),
            "transfer.total_count": .int(snapshot.totalCount),
            "transfer.failed_count": .int(snapshot.failedCount),
            "transfer.remove_after_backup_enabled": .bool(isRemoveAfterBackupEnabled)
        ]
        if let sessionDuration {
            attributes["transfer.session_duration_seconds"] = .double(sessionDuration)
        }
        switch cleanupResult {
        case .skipped:
            attributes["transfer.cleanup_result"] = .string("skipped")
        case .removed(let removedCount):
            attributes["transfer.cleanup_result"] = .string("removed")
            attributes["transfer.cleanup_removed_count"] = .int(removedCount)
        case .failed(let message):
            attributes["transfer.cleanup_result"] = .string("failed")
            attributes["transfer.cleanup_failure_message"] = .string(message)
        }
        return attributes
    }

    private func transferCompletionSpanStatus(for snapshot: TransferSnapshot) -> MobileTelemetrySpanStatus {
        snapshot.failedCount == 0 ? .ok : .error("transfer_completed_with_failures")
    }

    private func applyPairingStatusStateTransition(_ status: PairingStatus) {
        switch status.backupFlowState {
        case .pendingPairing:
            transitionBackupFlow(.pairingStarted)
        case .pairingMismatched:
            transitionBackupFlow(.pairingMismatchDetected)
        case .pairingCompleted:
            transitionBackupFlow(.pairingAccepted)
        case .pairingExpired:
            transitionBackupFlow(.pairingExpired)
        case .pairingStopped:
            transitionBackupFlow(.pairingStopped)
        case .transferInProgress:
            transitionBackupFlow(.transferStarted)
        case .transferStopped:
            transitionBackupFlow(.transferStopped)
        case .transferCompleted:
            transitionBackupFlow(.transferCompleted)
        case .transferFailed:
            transitionBackupFlow(.transferFailed)
        }
    }

    private func transitionBackupFlow(_ event: MobileBackupFlowEvent) {
        backupFlowStateMachine.transition(event)
    }

    func recordTelemetry(
        _ event: MobileTelemetryEvent,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        telemetryService.recordTelemetry(event, attributes: attributes)
    }

    func beginTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        telemetryService.beginTelemetrySpan(span, attributes: attributes)
    }

    private func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:],
        status: MobileTelemetrySpanStatus? = nil
    ) {
        telemetryService.endTelemetrySpan(span, attributes: attributes, status: status)
    }

    private func incrementTelemetryMetric(
        _ metric: MobileTelemetryMetric,
        by value: Int = 1,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        telemetryService.incrementTelemetryMetric(metric, by: value, attributes: attributes)
    }

    private func beginBackupSessionTelemetry() {
        telemetryService.beginBackupSessionTelemetry()
    }

    private func makeTelemetryContext() -> TelemetryContext {
        TelemetryContext(
            route: route,
            backupFlowState: backupFlowStateMachine.state,
            pairingStatus: pairingStatus,
            backupSession: backupSessionProvider.backupSession
        )
    }

    private func pushTelemetryContext() {
        telemetryContextProvider.updateContext(makeTelemetryContext())
    }

    func recordPageView(name: String) {
        recordTelemetry(
            .pageViewed,
            attributes: [
                "ui.view.kind": .string("page"),
                "ui.view.name": .string(name)
            ]
        )
    }

    func recordDialogView(name: String) {
        telemetryService.recordDialogView(name: name)
    }

    func recordInteraction(name: String, location: String) {
        telemetryService.recordInteraction(name: name, location: location)
    }

    private func flushTelemetry() {
        telemetryService.forceFlush()
    }

    private func configureMemoryWarningObservation() {
        memoryWarningObservationTask?.cancel()
        memoryWarningObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            ) {
                guard let self else {
                    return
                }
                await self.handleMemoryWarningNotification()
            }
        }
    }

    private func configureAppLifecycleObservation() {
        appLifecycleObservationTask?.cancel()
        appLifecycleObservationTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    do {
                        for try await _ in NotificationCenter.default.notifications(
                            named: UIApplication.didEnterBackgroundNotification
                        ) {
                            guard let self else {
                                return
                            }
                            await self.flushTelemetry()
                        }
                    } catch {}
                }

                group.addTask { [weak self] in
                    do {
                        for try await _ in NotificationCenter.default.notifications(
                            named: UIApplication.didBecomeActiveNotification
                        ) {
                            guard let self else {
                                return
                            }
                            await self.handleAppDidBecomeActive()
                        }
                    } catch {}
                }

                group.addTask { [weak self] in
                    do {
                        for try await _ in NotificationCenter.default.notifications(
                            named: UIApplication.willTerminateNotification
                        ) {
                            guard let self else {
                                return
                            }
                            await self.flushTelemetry()
                        }
                    } catch {}
                }

                await group.waitForAll()
            }
        }
    }

    private func handleMemoryWarningNotification() {
        recordTelemetry(
            .memoryWarningReceived,
            attributes: [
                "transfer.is_active": .bool(route == .transfer)
            ]
        )
        let transferService = transferService
        Task.detached(priority: .utility) {
            await transferService.handleMemoryWarning()
        }
    }

    func handleAppDidBecomeActive() async {
        let pairingService = pairingService
        let shouldRecoverTransferTransport = route == .transfer
        let transferService = transferService
        Task.detached(priority: .utility) {
            await pairingService.primeNetworkAccess()
            if shouldRecoverTransferTransport {
                await transferService.handleAppDidBecomeActive()
            }
        }
    }

    private func currentTransferSnapshot() async -> TransferSnapshot {
        await transferService.progressSnapshot() ?? .empty(transport: pairingStatus.transport ?? .lan)
    }

    private func pairingStatus(for session: BackupSession) -> PairingStatus {
        PairingStatus(
            backupFlowState: backupFlowState(for: session.status),
            desktopName: session.desktopName,
            sessionID: session.sessionID,
            transport: nil
        )
    }

    private func backupFlowState(for status: BackupSessionStatus) -> MobileBackupFlowState {
        switch status {
        case .paired:
            return .pairingCompleted
        case .stopped:
            return .transferStopped
        case .completed:
            return .transferCompleted
        case .failed:
            return .transferFailed
        }
    }
}
