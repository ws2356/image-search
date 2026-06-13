import Foundation
import UIKit
import Combine
import ISFromPC
import Common

@MainActor
final class MobileAppModel: ObservableObject, NavigatorFactory {
    @Published private(set) var route: AppRoute = .home {
        didSet { pushTelemetryContext() }
    }

    @Published var isShowingIncomingLinkReplacementConfirmation = false
    @Published private(set) var activeUpdatePrompt: AppUpdatePrompt?
    @Published var instantShareQRPayload: QRClaimPayload?

    private var hasLoaded = false
    private var hasFinishedLoad = false
    private var hasScheduledLaunchUpdateCheck = false
    private var pendingIncomingUniversalLinkPayload: String?
    private var isProcessingIncomingUniversalLink = false
    private let universalLinkHost = "dl.boldman.net"
    private static let appStoreURL = URL(string: "https://apps.apple.com/app/id6764228721")!
    let backupSessionProvider: BackupSessionProviding
    private let qrCodePayloadDecoder: QRCodePayloadDecoding
    let pairingService: PairingService
    let permissionService: PermissionService
    let transferService: TransferService
    private let appUpdateChecker: AppUpdateChecking
    private let appVersionProvider: AppVersionProviding
    private let telemetryContextProvider: TelemetryContextProvider
    private let telemetryService: TelemetryService
    private let appIdentityProvider: AppIdentityProviding
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
        appUpdateChecker: AppUpdateChecking,
        appVersionProvider: AppVersionProviding,
        telemetryService: TelemetryService,
        telemetryContextProvider: TelemetryContextProvider,
        appIdentityProvider: AppIdentityProviding
    ) {
        self.backupSessionProvider = backupSessionProvider
        self.qrCodePayloadDecoder = qrCodePayloadDecoder
        self.pairingService = pairingService
        self.permissionService = permissionService
        self.transferService = transferService
        self.appUpdateChecker = appUpdateChecker
        self.appVersionProvider = appVersionProvider
        self.telemetryContextProvider = telemetryContextProvider
        self.telemetryService = telemetryService
        self.appIdentityProvider = appIdentityProvider
        self.backupSessionObserver = backupSessionProvider.currentBackupSessionPublisher
            .sink { [weak self] session in
                self?.pushTelemetryContext()
                self?.recordDiagnosticCheckpoint(
                    area: "backup_session_observed",
                    attributes: self?.diagnosticAttributes(
                        backupSession: session,
                        extra: [
                            "diagnostic.trigger": .string("backup_session_publisher")
                        ]
                    ) ?? [:]
                )
            }
        pushTelemetryContext()
        configureMemoryWarningObservation()
        configureAppLifecycleObservation()
    }

    deinit {
        memoryWarningObservationTask?.cancel()
        appLifecycleObservationTask?.cancel()
    }
    
    /// protocol NavigatorFactory
    func createNavigator() -> Navigator {
        return NavigatorImpl(vm: self)
    }
    
    class NavigatorImpl: Navigator {
        private weak var vm: MobileAppModel?
        init(vm: MobileAppModel? = nil) {
            self.vm = vm
        }
        func requestExit() {
            vm?.instantShareQRPayload = nil
        }
    }
    
    func onHomeCompleted(with result: HomePageResult) async {
        switch result.result {
        case .success(let target):
            switch target {
            case .backupScan:
                await openScanFlow()
            case .genericScan:
                route = .genericScan
            }
        case .failure:
            break
        }
    }

    func onGenericQRScanCompleted(with result: GenericQRScanPageResult) async {
        switch result.result {
        case .success(let qrString):
            if let url = URL(string: qrString), let payload = QRClaimPayload(universalLinkURL: url) {
                self.instantShareQRPayload = payload
                self.route = .home
                return
            }
            beginBackupSessionTelemetry()
            await showPairingPage(qrString: qrString)
        case .failure(.cancel):
            await returnHome()
        case .failure(.scannerFailed):
            presentErrorSummary(
                title: "Scanner failed",
                message: "The camera scanner couldn't continue. Try again or return home."
            )
        case .failure:
            presentErrorSummary(
                title: "Scanner error",
                message: "An unexpected error occurred. Try again or return home."
            )
        }
    }

    func onScanningCompleted(with result: ScanningPageResult) async {
        switch result.result {
        case .success(let qrString):
            if let url = URL(string: qrString), let payload = QRClaimPayload(universalLinkURL: url) {
                self.instantShareQRPayload = payload
                self.route = .home
                return
            }
            await showPairingPage(qrString: qrString)
        case .failure(.cancel):
            await returnHome()
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
        recordDiagnosticCheckpoint(
            area: "pairing_result_received",
            attributes: diagnosticAttributes(
                backupSession: backupSessionProvider.currentBackupSession,
                extra: pairingResultDiagnosticAttributes(result)
            )
        )
        switch result.result {
        case .success(let pairingResponse):
            transitionBackupFlow(.pairingAccepted)
            await backupSessionProvider.saveBackupSession(
                status: .pairingCompleted,
                sessionID: pairingResponse.sessionID,
                desktopName: pairingResponse.desktopName
            )
            route = .permissions
            recordTelemetry(.pairingSucceeded)
            endTelemetrySpan(.pairingFlow, status: .ok)

        case .failure(.cancel):
            await returnHome()

        case .failure(.rejected(let message)):
            transitionBackupFlow(.pairingStopped)
            reportPairingFailure(
                reason: "desktop_stopped_pairing",
                pairingAttributes: [
                    "pairing.failure_message": .string(message)
                ]
            )
            endTelemetrySpan(
                .backupSession,
                attributes: [
                    "backup.failure_reason": .string("desktop_stopped_pairing")
                ],
                status: .error("desktop_stopped_pairing")
            )
            await backupSessionProvider.saveBackupSession(
                status: .pairingStopped,
                sessionID: backupSessionProvider.currentBackupSession?.sessionID,
                desktopName: backupSessionProvider.currentBackupSession?.desktopName
            )
            presentErrorSummary(
                title: PairingError.rejected(message: message).title,
                message: message
            )

        case .failure(.expired(let message)):
            transitionBackupFlow(.pairingExpired)
            reportPairingFailure(
                reason: PairingError.expired(message: message).title,
                pairingAttributes: [
                    "pairing.failure_message": .string(message)
                ]
            )
            presentErrorSummary(
                title: PairingError.expired(message: message).title,
                message: message
            )

        case .failure(let error):
            transitionBackupFlow(.pairingFailed)
            reportPairingFailure(
                reason: error.title,
                pairingAttributes: [
                    "pairing.failure_message": .string(error.message)
                ]
            )
            await backupSessionProvider.saveBackupSession(
                status: .pairingFailed,
                sessionID: backupSessionProvider.currentBackupSession?.sessionID,
                desktopName: backupSessionProvider.currentBackupSession?.desktopName
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
            await handleCompletedTransfer()
        case .failure(.stopConfirmed):
            await handleStoppedTransfer()
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

    var routeName: String {
        switch route {
        case .home:
            return "home"
        case .scan:
            return "scan"
        case .genericScan:
            return "generic_scan"
        case .pair:
            return "pair"
        case .permissions:
            return "permissions"
        case .transfer:
            return "transfer"
        case .completed:
            return "completed"
        case .error(_):
            return "error"
        }
    }

    func load() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        try? await appIdentityProvider.ensureSelfIdentity()
        do {
            let cert = try appIdentityProvider.selfCertificate()
            DebugPrintCert(cert)
        } catch (let error) {
            LocalLog.error("[identity] failed to get cert: \(error)")
        }
        
        await backupSessionProvider.load()
        await permissionService.setRemoveAfterBackupEnabled(false)
        let backupSession = backupSessionProvider.currentBackupSession
        if let backupSession {
            backupFlowStateMachine = MobileBackupFlowStateMachine(
                state: backupSession.status
            )
        } else {
            backupFlowStateMachine = MobileBackupFlowStateMachine()
        }
        route = .home
        recordDiagnosticCheckpoint(
            area: "app_load_completed",
            attributes: diagnosticAttributes(backupSession: backupSessionProvider.lastBackupSession)
        )
        hasFinishedLoad = true

        // Process any universal link that arrived before load completed.
        if let pendingPayload = pendingIncomingUniversalLinkPayload {
            pendingIncomingUniversalLinkPayload = nil
            if let url = URL(string: pendingPayload) {
                await handleIncomingUniversalLink(url)
            }
        }

        let pairingService = pairingService
        Task.detached(priority: .utility) {
            await pairingService.primeNetworkAccess()
        }
        recordTelemetry(.appLaunched)
        scheduleLaunchUpdateCheckIfNeeded()
    }

    func openScanFlow() async {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        beginBackupSessionTelemetry()
        transitionBackupFlow(.pairingStarted)
        route = .scan
        recordTelemetry(.scanStarted)
    }

    func handleIncomingUniversalLink(_ url: URL) async {
        guard isSupportedUniversalLink(url) else {
            return
        }

        // Otherwise treat as pairing universal link
        let payload = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            return
        }

        // Stash the link if load() hasn't completed yet — it will process it after setting route = .home.
        if !hasFinishedLoad {
            pendingIncomingUniversalLinkPayload = payload
            return
        }

        // Check if this is a /share link (instant share / QR claim)
        if let claimPayload = QRClaimPayload(universalLinkURL: url) {
            self.instantShareQRPayload = claimPayload
            return
        }

        if route == .transfer {
            pendingIncomingUniversalLinkPayload = payload
            isShowingIncomingLinkReplacementConfirmation = true
            recordDiagnosticCheckpoint(
                area: "incoming_universal_link_deferred",
                attributes: diagnosticAttributes(
                    backupSession: backupSessionProvider.currentBackupSession,
                    extra: [
                        "diagnostic.trigger": .string("handle_incoming_universal_link"),
                        "pairing.payload_length": .int(payload.count)
                    ]
                )
            )
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
        recordTelemetry(.pairingStarted)
        recordDiagnosticCheckpoint(
            area: "pairing_page_presented",
            attributes: diagnosticAttributes(
                backupSession: backupSessionProvider.currentBackupSession,
                extra: [
                    "pairing.payload_length": .int(qrString.count)
                ]
            )
        )
    }

    private func abortPreflightAndReturnHome(reason: String) async {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        await permissionService.setRemoveAfterBackupEnabled(false)
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
            status: .transferStopped,
            sessionID: backupSessionProvider.currentBackupSession?.sessionID,
            desktopName: backupSessionProvider.currentBackupSession?.desktopName
        )
    }

    private func handleStoppedTransfer() async {
        guard route == .transfer else { return }
        await finalizeStoppedTransfer(reason: "user_requested")
    }

    private func stopTransferForIncomingLinkReplacementIfNeeded() async {
        guard route == .transfer else {
            return
        }
        _ = await transferService.stopTransfer()
        await finalizeStoppedTransfer(reason: "replaced_by_universal_link")
    }

    private func finalizeStoppedTransfer(reason: String) async {
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
            status: .transferStopped,
            sessionID: backupSessionProvider.currentBackupSession?.sessionID,
            desktopName: backupSessionProvider.currentBackupSession?.desktopName
        )
    }

    var backupFlowState: MobileBackupFlowState {
        backupFlowStateMachine.state
    }

    private func handleCompletedTransfer() async {
        guard route == .transfer else { return }
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
            status: snapshot.failedCount == 0 ? .transferCompleted : .transferFailed,
            sessionID: backupSessionProvider.currentBackupSession?.sessionID,
            desktopName: backupSessionProvider.currentBackupSession?.desktopName
        )
    }

    func returnHome() async {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        await permissionService.setRemoveAfterBackupEnabled(false)
        transitionBackupFlow(.resetToPendingPairing)
        route = .home
    }

    func dismissUpdatePrompt() {
        guard let activeUpdatePrompt, !activeUpdatePrompt.required else {
            return
        }
        recordInteraction(name: "update_prompt_dismissed", location: "update_prompt")
        self.activeUpdatePrompt = nil
    }

    func updateDestinationForActivePrompt() -> URL? {
        guard let activeUpdatePrompt else {
            return nil
        }
        recordInteraction(name: "update_prompt_update_tapped", location: "update_prompt")
        if !activeUpdatePrompt.required {
            self.activeUpdatePrompt = nil
        }
        return activeUpdatePrompt.appStoreURL
    }

    private func presentErrorSummary(title: String, message: String) {
        route = .error(ErrorSummary(title: title, message: message))
    }

    private func isSupportedUniversalLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host == universalLinkHost
    }

    private func processIncomingUniversalLinkPayload(_ payload: String) async {
        guard !isProcessingIncomingUniversalLink else {
            recordDiagnosticCheckpoint(
                area: "incoming_universal_link_skipped",
                attributes: diagnosticAttributes(
                    backupSession: backupSessionProvider.currentBackupSession,
                    extra: [
                        "diagnostic.trigger": .string("process_incoming_universal_link_payload"),
                        "pairing.skip_reason": .string("already_processing"),
                        "pairing.payload_length": .int(payload.count)
                    ]
                )
            )
            return
        }
        isProcessingIncomingUniversalLink = true
        recordDiagnosticCheckpoint(
            area: "incoming_universal_link_processing_started",
            attributes: diagnosticAttributes(
                backupSession: backupSessionProvider.currentBackupSession,
                extra: [
                    "diagnostic.trigger": .string("process_incoming_universal_link_payload"),
                    "pairing.payload_length": .int(payload.count)
                ]
            )
        )
        defer {
            isProcessingIncomingUniversalLink = false
            recordDiagnosticCheckpoint(
                area: "incoming_universal_link_processing_finished",
                attributes: diagnosticAttributes(
                    backupSession: backupSessionProvider.currentBackupSession,
                    extra: [
                        "diagnostic.trigger": .string("process_incoming_universal_link_payload"),
                        "pairing.payload_length": .int(payload.count)
                    ]
                )
            )
        }

        await openScanFlow()
        await showPairingPage(qrString: payload)
    }

    private func triggerTransfer() async {
        transitionBackupFlow(.transferStarted)
        route = .transfer
        let isRemoveAfterBackupEnabled = await permissionService.removeAfterBackupEnabled()
        let isIncompleteLibrary = await permissionService.loadPermissionSummary().mediaScope != .full
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

    private func pairingResultDiagnosticAttributes(_ result: PairingPageResult) -> MobileTelemetryAttributes {
        switch result.result {
        case .success(let response):
            return [
                "pairing.result": .string("success"),
                "pairing.transport": .string(response.transport.rawValue),
                "pairing.desktop_name_present": .bool(!response.desktopName.isEmpty)
            ]
        case .failure(let error):
            return [
                "pairing.result": .string("failure"),
                "pairing.failure_reason": .string(error.title),
                "pairing.failure_message": .string(error.message)
            ]
        }
    }

    private func diagnosticAttributes(
        backupSession: BackupSession?,
        extra: MobileTelemetryAttributes = [:]
    ) -> MobileTelemetryAttributes {
        var attributes: MobileTelemetryAttributes = [
            "app.route": .string(routeName),
            "backup.flow_state": .string(backupFlowState.rawValue),
            "app.has_pending_universal_link_payload": .bool(pendingIncomingUniversalLinkPayload?.isEmpty == false),
            "app.is_processing_incoming_universal_link": .bool(isProcessingIncomingUniversalLink),
            "app.is_showing_incoming_link_replacement_confirmation": .bool(isShowingIncomingLinkReplacementConfirmation)
        ]
        if let backupSession {
            attributes["backup.session_present"] = .bool(true)
            attributes["backup.session_status"] = .string(backupSession.status.rawValue)
            attributes["backup.session_id_present"] = .bool(backupSession.sessionID?.isEmpty == false)
            attributes["backup.desktop_name_present"] = .bool(!(backupSession.desktopName ?? "").isEmpty)
        } else {
            attributes["backup.session_present"] = .bool(false)
        }
        for (key, value) in extra {
            attributes[key] = value
        }
        return attributes
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
            backupSession: backupSessionProvider.currentBackupSession
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

    private func recordDiagnosticCheckpoint(
        area: String,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        var diagnosticAttributes = attributes
        diagnosticAttributes["diagnostic.area"] = .string(area)
        telemetryService.recordTelemetry(.diagnosticCheckpoint, attributes: diagnosticAttributes)
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
        if let transferSnapshot = await transferService.progressSnapshot() {
            return transferSnapshot
        }
        let fallbackTransport = await transferService.currentTransport() ?? .lan
        return .empty(transport: fallbackTransport)
    }

    private func scheduleLaunchUpdateCheckIfNeeded() {
        guard !hasScheduledLaunchUpdateCheck else {
            return
        }
        hasScheduledLaunchUpdateCheck = true

        Task { [weak self] in
            await self?.checkForLaunchUpdatePrompt()
        }
    }

    private func checkForLaunchUpdatePrompt() async {
        guard let currentVersion = appVersionProvider.currentVersion(),
              !currentVersion.isEmpty
        else {
            recordDiagnosticCheckpoint(
                area: "app_update_check_skipped",
                attributes: [
                    "app.update_check_reason": .string("missing_current_version")
                ]
            )
            return
        }

        do {
            let requirement = try await appUpdateChecker.fetchVersionRequirement()
            guard let prompt = requirement.promptIfNeeded(
                currentVersion: currentVersion,
                appStoreURL: Self.appStoreURL
            ) else {
                recordDiagnosticCheckpoint(
                    area: "app_update_not_needed",
                    attributes: [
                        "app.current_version": .string(currentVersion),
                        "app.minimum_supported_version": .string(requirement.minimumVersion),
                        "app.update_required": .bool(requirement.required)
                    ]
                )
                return
            }

            activeUpdatePrompt = prompt
            recordDialogView(name: prompt.required ? "required_update_prompt" : "optional_update_prompt")
            recordDiagnosticCheckpoint(
                area: "app_update_prompt_presented",
                attributes: [
                    "app.current_version": .string(currentVersion),
                    "app.minimum_supported_version": .string(prompt.minimumVersion),
                    "app.update_required": .bool(prompt.required)
                ]
            )
        } catch {
            recordDiagnosticCheckpoint(
                area: "app_update_check_failed",
                attributes: [
                    "app.current_version": .string(currentVersion),
                    "app.update_error": .string(String(describing: error))
                ]
            )
        }
    }

}
