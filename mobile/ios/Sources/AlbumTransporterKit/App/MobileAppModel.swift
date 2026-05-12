import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Combine

@MainActor
final class MobileAppModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home
    @Published private(set) var homeSummary = HomeSummary.firstLaunch
    @Published var permissionSummary = PermissionSummary.demo
    @Published private(set) var removeAfterBackupEnabled = false
    @Published private(set) var pairingStatus = PairingStatus.idle
    @Published private(set) var errorSummary = ErrorSummary.generic
    @Published var scannedQRCodeValue = ""

    @Published var isShowingIncomingLinkReplacementConfirmation = false

    private var hasLoaded = false
    private var pendingIncomingUniversalLinkPayload: String?
    private var isProcessingIncomingUniversalLink = false
    private let universalLinkHost = "dl.boldman.net"
    private let stateStore: AppStateStore
    private let qrCodePayloadDecoder: QRCodePayloadDecoding
    private let pairingService: PairingService
    let permissionService: PermissionService
    private let transferService: TransferService
    private let sideEffectWorker: MobileAppSideEffectWorker
    private var backupFlowStateMachine = MobileBackupFlowStateMachine()
#if canImport(UIKit)
    private var memoryWarningObservationTask: Task<Void, Never>?
    private var appLifecycleObservationTask: Task<Void, Never>?
#endif

    init(
        stateStore: AppStateStore,
        qrCodePayloadDecoder: QRCodePayloadDecoding,
        pairingService: PairingService,
        permissionService: PermissionService,
        transferService: TransferService,
        telemetryClient: TelemetryClient
    ) {
        self.stateStore = stateStore
        self.qrCodePayloadDecoder = qrCodePayloadDecoder
        self.pairingService = pairingService
        self.permissionService = permissionService
        self.transferService = transferService
        self.sideEffectWorker = MobileAppSideEffectWorker(
            stateStore: stateStore,
            telemetryClient: telemetryClient
        )
        configureMemoryWarningObservation()
        configureAppLifecycleObservation()
    }

    deinit {
#if canImport(UIKit)
        memoryWarningObservationTask?.cancel()
        appLifecycleObservationTask?.cancel()
#endif
    }
    
    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async {
        switch page {
        case .home:
            switch result {
            case .success:
                await openScanFlow()
            case .cancel:
                print("Should not be here - home.cancel")
            case .failure:
                print("Should not be here - home.failure")
            }

        case .scan:
            switch result {
            case .success:
                await beginPairing()
            case .cancel:
                await returnHome()
            case .failure:
                presentErrorSummary(
                    title: "Scanner failed",
                    message: "The camera scanner couldn't continue. Restart the backup session or return home."
                )
            }

        case .pair:
            switch result {
            case .success:
                await openScanFlow()
            case .cancel:
                await returnHome()
            case .failure:
                presentErrorSummary(
                    title: "Pairing flow failed",
                    message: "AuBackup couldn't continue the pairing flow. Restart the backup session or return home."
                )
            }
            
        case .permissions:
            switch result {
            case .success:
                if target == .removeTransferredMedia {
                    setRemoveAfterBackupEnabled(true)
                } else if target == .keepOriginals {
                    setRemoveAfterBackupEnabled(false)
                }
                await triggerTransfer()
            case .cancel:
                let reason = target == .lowBatteryDeclined ? "low_battery_declined" : "permissions_cancelled"
                await abortPreflightAndReturnHome(reason: reason)
            case .failure:
                presentErrorSummary(
                    title: "Preflight failed",
                    message: "AuBackup couldn't complete backup preflight. Restart the backup session or return home."
                )
            }
            
        case .transfer:
            switch result {
            case .success:
                if target == .primary {
                    requestStopTransfer()
                } else if target == .secondary {
                    await finalizeCompletedTransfer()
                }
            case .cancel:
                break
            case .failure:
                if target == .stopTransferConfirmed {
                    await finalizeStoppedTransfer()
                } else {
                    presentErrorSummary(
                        title: "Transfer failed",
                        message: "AuBackup couldn't continue this transfer. Restart the backup session or return home."
                    )
                }
            }

        case .completed:
            switch result {
            case .success, .cancel:
                await returnHome()
            case .failure:
                presentErrorSummary(
                    title: "Completion failed",
                    message: "AuBackup couldn't finish this completion step. Restart the backup session or return home."
                )
            }

        case .error:
            switch result {
            case .success:
                await openScanFlow()
            case .cancel, .failure:
                await returnHome()
            }
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

    func load() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        let snapshot = await stateStore.loadLaunchSnapshot()
        await apply(snapshot: snapshot)
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
            phase: .scanning,
            backupFlowState: .pendingPairing,
            desktopName: homeSummary.desktopName,
            sessionID: nil,
            transport: nil,
            message: "Point the camera at the desktop QR code shown in the PC app."
        )
        route = .scan
        recordTelemetry(.scanStarted)
        persistSnapshot()
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

    func beginPairing() async {
        beginTelemetrySpan(.pairingFlow)
        transitionBackupFlow(.pairingStarted)
        route = .pair
        pairingStatus = PairingStatus(
            phase: .pairing,
            backupFlowState: .pendingPairing,
            desktopName: homeSummary.desktopName,
            sessionID: nil,
            transport: nil,
            message: "Validating the QR payload and establishing a secure local session with the desktop."
        )
        recordTelemetry(.pairingStarted)

        let payloadResult = qrCodePayloadDecoder.decode(scannedValue: scannedQRCodeValue)

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                let failureMessage = error.message
                pairingStatus = PairingStatus(
                    phase: .failed,
                    backupFlowState: .pendingPairing,
                    desktopName: homeSummary.desktopName,
                    sessionID: nil,
                    transport: nil,
                    message: failureMessage
                )
                applyPairingStatusStateTransition(pairingStatus)
                recordTelemetry(
                    .pairingFailed,
                    attributes: [
                        "pairing.failure_reason": .string("invalid_qr_payload"),
                        "pairing.failure_message": .string(failureMessage)
                    ]
                )
                incrementTelemetryMetric(
                    .backupFailures,
                    attributes: [
                        "backup.failure_reason": .string("invalid_qr_payload")
                    ]
                )
                endTelemetrySpan(
                    .pairingFlow,
                    attributes: [
                        "pairing.failure_reason": .string("invalid_qr_payload")
                    ],
                    status: .error("invalid_qr_payload")
                )
            }
            persistSnapshot()
            return
        }

        let result = await pairingService.startPairing(using: payload)
        pairingStatus = result
        applyPairingStatusStateTransition(result)
        persistSnapshot()

        if result.backupFlowState == .pairingStopped {
            homeSummary.pendingItemCount = nil
            route = .home
            recordTelemetry(
                .pairingFailed,
                attributes: [
                    "pairing.failure_reason": .string("desktop_stopped_pairing")
                ]
            )
            incrementTelemetryMetric(
                .backupFailures,
                attributes: [
                    "backup.failure_reason": .string("desktop_stopped_pairing")
                ]
            )
            endTelemetrySpan(
                .pairingFlow,
                attributes: [
                    "pairing.failure_reason": .string("desktop_stopped_pairing")
                ],
                status: .error("desktop_stopped_pairing")
            )
            endTelemetrySpan(
                .backupSession,
                attributes: [
                    "backup.failure_reason": .string("desktop_stopped_pairing")
                ],
                status: .error("desktop_stopped_pairing")
            )
            persistSnapshot()
            return
        }

        guard result.phase == .paired else {
            recordTelemetry(
                .pairingFailed,
                attributes: [
                    "pairing.failure_reason": .string("unexpected_pairing_phase"),
                    "pairing.result_phase": .string(result.phase.rawValue)
                ]
            )
            incrementTelemetryMetric(
                .backupFailures,
                attributes: [
                    "backup.failure_reason": .string("unexpected_pairing_phase")
                ]
            )
            endTelemetrySpan(
                .pairingFlow,
                attributes: [
                    "pairing.failure_reason": .string("unexpected_pairing_phase"),
                    "pairing.result_phase": .string(result.phase.rawValue)
                ],
                status: .error("unexpected_pairing_phase")
            )
            return
        }

        homeSummary.desktopName = result.desktopName
        permissionSummary = await permissionService.loadPermissionSummary()
        route = .permissions

        recordTelemetry(.pairingSucceeded)
        endTelemetrySpan(.pairingFlow, status: .ok)
        persistSnapshot()
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        guard removeAfterBackupEnabled != isEnabled else {
            return
        }
        removeAfterBackupEnabled = isEnabled
        persistSnapshot()
    }

    func abortPreflightAndReturnHome(reason: String) async {
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        let interruptionSnapshot = TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: pairingStatus.transport ?? .lan,
            etaDescription: nil,
            statusMessage: "Backup canceled before transfer started.",
            guidanceMessage: "Scan again when you are ready to start another backup session.",
            isIncompleteLibrary: permissionSummary.mediaScope != .full
        )
        _ = await transferService.stopTransfer(current: interruptionSnapshot)
        await transferService.stageTransferSnapshot(interruptionSnapshot)
        await transferService.stageTransferCompletionState(nil)
        transitionBackupFlow(.transferStopped)
        route = .home
        recordTelemetry(
            .transferStopped,
            attributes: [
                "transfer.stop_reason": .string(reason)
            ]
        )
        incrementTelemetryMetric(
            .backupFailures,
            attributes: [
                "backup.failure_reason": .string(reason)
            ]
        )
        endTelemetrySpan(
            .backupPreflight,
            attributes: [
                "backup.failure_reason": .string(reason)
            ],
            status: .error(reason)
        )
        endTelemetrySpan(
            .backupSession,
            attributes: [
                "backup.failure_reason": .string(reason)
            ],
            status: .error(reason)
        )
        persistSnapshot()
    }

    func requestStopTransfer() {
        recordTelemetry(.transferStopRequested)
    }

    private func finalizeStoppedTransfer() async {
        await transferService.stageTransferCompletionState(nil)
        transitionBackupFlow(.transferStopped)
        route = .home

        recordTelemetry(
            .transferStopped,
            attributes: [
                "transfer.stop_reason": .string("user_requested")
            ]
        )
        incrementTelemetryMetric(
            .backupFailures,
            attributes: [
                "backup.failure_reason": .string("user_requested")
            ]
        )
        endTelemetrySpan(
            .transferFlow,
            attributes: [
                "transfer.stop_reason": .string("user_requested")
            ],
            status: .error("user_requested")
        )
        endTelemetrySpan(
            .backupSession,
            attributes: [
                "backup.failure_reason": .string("user_requested")
            ],
            status: .error("user_requested")
        )
        persistSnapshot()
    }

    private func stopTransferForIncomingLinkReplacementIfNeeded() async {
        guard route == .transfer else {
            return
        }
        let snapshot = await currentTransferSnapshot()
        _ = await transferService.stopTransfer(current: snapshot)
        await transferService.stageTransferSnapshot(snapshot)
        await transferService.stageTransferCompletionState(nil)
        transitionBackupFlow(.transferStopped)
        route = .home

        recordTelemetry(
            .transferStopped,
            attributes: [
                "transfer.stop_reason": .string("replaced_by_universal_link")
            ]
        )
        incrementTelemetryMetric(
            .backupFailures,
            attributes: [
                "backup.failure_reason": .string("replaced_by_universal_link")
            ]
        )
        endTelemetrySpan(
            .transferFlow,
            attributes: [
                "transfer.stop_reason": .string("replaced_by_universal_link")
            ],
            status: .error("replaced_by_universal_link")
        )
        endTelemetrySpan(
            .backupSession,
            attributes: [
                "backup.failure_reason": .string("replaced_by_universal_link")
            ],
            status: .error("replaced_by_universal_link")
        )
        persistSnapshot()
    }

    var transferServiceForPageModels: TransferService {
        transferService
    }

    var backupFlowState: MobileBackupFlowState {
        backupFlowStateMachine.state
    }

    var transferServiceForTransferView: TransferService {
        transferService
    }

    private func finalizeCompletedTransfer() async {
        let completionState = await transferService.transferCompletionState()
        let snapshot: TransferSnapshot
        if let completedSnapshot = completionState?.snapshot {
            snapshot = completedSnapshot
        } else {
            snapshot = await currentTransferSnapshot()
        }
        let cleanupResult = completionState?.cleanupResult ?? .skipped
        let sessionDuration = completionState?.sessionDuration
        transitionBackupFlow(snapshot.failedCount == 0 ? .transferCompleted : .transferFailed)
        homeSummary = .completed(
            desktopName: homeSummary.desktopName,
            permissionScope: permissionSummary.mediaScope,
            lastBackupDescription: "Last backup completed just now."
        )
        route = .completed

        var completionAttributes: MobileTelemetryAttributes = [
            "transfer.transferred_count": .int(snapshot.transferredCount),
            "transfer.total_count": .int(snapshot.totalCount),
            "transfer.failed_count": .int(snapshot.failedCount),
            "transfer.remove_after_backup_enabled": .bool(removeAfterBackupEnabled)
        ]
        if let sessionDuration {
            completionAttributes["transfer.session_duration_seconds"] = .double(sessionDuration)
        }
        switch cleanupResult {
        case .skipped:
            completionAttributes["transfer.cleanup_result"] = .string("skipped")
        case .removed(let removedCount):
            completionAttributes["transfer.cleanup_result"] = .string("removed")
            completionAttributes["transfer.cleanup_removed_count"] = .int(removedCount)
        case .failed(let message):
            completionAttributes["transfer.cleanup_result"] = .string("failed")
            completionAttributes["transfer.cleanup_failure_message"] = .string(message)
        }
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
            status: snapshot.failedCount == 0 ? .ok : .error("transfer_completed_with_failures")
        )
        endTelemetrySpan(
            .backupSession,
            attributes: completionAttributes,
            status: snapshot.failedCount == 0 ? .ok : .error("transfer_completed_with_failures")
        )
        persistSnapshot()
    }

    func returnHome() async {
        await transferService.stageTransferCompletionState(nil)
        pendingIncomingUniversalLinkPayload = nil
        isShowingIncomingLinkReplacementConfirmation = false
        errorSummary = .generic
        transitionBackupFlow(.resetToPendingPairing)
        route = .home
        persistSnapshot()
    }

    private func presentErrorSummary(title: String, message: String) {
        errorSummary = ErrorSummary(title: title, message: message)
        route = .error
        persistSnapshot()
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
        scannedQRCodeValue = payload
        await beginPairing()
    }

    private func triggerTransfer() async {
        transitionBackupFlow(.transferStarted)
        route = .transfer
        let initialSnapshot = TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: pairingStatus.transport ?? .lan,
            etaDescription: nil,
            statusMessage: "Preparing the local media backup with the paired desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: permissionSummary.mediaScope != .full
        )
        await transferService.stageTransferSnapshot(initialSnapshot)
        await transferService.stageTransferCompletionState(nil)
        endTelemetrySpan(.backupPreflight, status: .ok)
        beginTelemetrySpan(.transferFlow)
        recordTelemetry(
            .transferStarted,
            attributes: [
                "transfer.is_incomplete_library": .bool(permissionSummary.mediaScope != .full)
            ]
        )
        persistSnapshot()
    }

    private func apply(snapshot: LaunchSnapshot) async {
        homeSummary = snapshot.homeSummary
        permissionSummary = snapshot.permissionSummary
        removeAfterBackupEnabled = snapshot.removeAfterBackupEnabled
        pairingStatus = snapshot.pairingStatus
        await transferService.stageTransferSnapshot(snapshot.transferSnapshot)
        await transferService.stageTransferCompletionState(nil)
        errorSummary = .generic
        backupFlowStateMachine = MobileBackupFlowStateMachine(
            state: inferredBackupFlowState(from: snapshot)
        )
        route = .home
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

    private func inferredBackupFlowState(from snapshot: LaunchSnapshot) -> MobileBackupFlowState {
        return snapshot.pairingStatus.backupFlowState
    }

    func persistSnapshot() {
        let homeSummary = homeSummary
        let permissionSummary = permissionSummary
        let pairingStatus = pairingStatus
        let removeAfterBackupEnabled = removeAfterBackupEnabled
        let transferService = transferService
        let worker = sideEffectWorker
        Task.detached(priority: .utility) {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let snapshot = LaunchSnapshot(
                homeSummary: homeSummary,
                permissionSummary: permissionSummary,
                pairingStatus: pairingStatus,
                transferSnapshot: transferSnapshot,
                removeAfterBackupEnabled: removeAfterBackupEnabled
            )
            await worker.persist(snapshot: snapshot)
        }
    }

    func recordTelemetry(
        _ event: MobileTelemetryEvent,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let contextState = makeTelemetryContextState()
        let transferService = transferService
        let worker = sideEffectWorker
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                contextState: contextState,
                transferSnapshot: transferSnapshot
            )
            await worker.record(event: event, attributes: mergedAttributes)
        }
    }

    func beginTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let contextState = makeTelemetryContextState()
        let transferService = transferService
        let worker = sideEffectWorker
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                contextState: contextState,
                transferSnapshot: transferSnapshot
            )
            await worker.begin(span: span, attributes: mergedAttributes)
        }
    }

    private func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes = [:],
        status: MobileTelemetrySpanStatus? = nil
    ) {
        let contextState = makeTelemetryContextState()
        let transferService = transferService
        let worker = sideEffectWorker
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                contextState: contextState,
                transferSnapshot: transferSnapshot
            )
            await worker.end(span: span, attributes: mergedAttributes, status: status)
        }
    }

    private func incrementTelemetryMetric(
        _ metric: MobileTelemetryMetric,
        by value: Int = 1,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        let contextState = makeTelemetryContextState()
        let transferService = transferService
        let worker = sideEffectWorker
        Task {
            let transferSnapshot = await transferService.progressSnapshot() ?? .demo
            let mergedAttributes = mergedTelemetryAttributes(
                extraAttributes: attributes,
                contextState: contextState,
                transferSnapshot: transferSnapshot
            )
            await worker.increment(metric: metric, by: value, attributes: mergedAttributes)
        }
    }

    private func beginBackupSessionTelemetry() {
        beginTelemetrySpan(.backupSession)
        incrementTelemetryMetric(.backupAttempts)
    }

    private struct TelemetryContextState {
        let route: AppRoute
        let homeSummary: HomeSummary
        let pairingStatus: PairingStatus
        let permissionSummary: PermissionSummary
        let removeAfterBackupEnabled: Bool
    }

    private func makeTelemetryContextState() -> TelemetryContextState {
        TelemetryContextState(
            route: route,
            homeSummary: homeSummary,
            pairingStatus: pairingStatus,
            permissionSummary: permissionSummary,
            removeAfterBackupEnabled: removeAfterBackupEnabled
        )
    }

    private func telemetryContextAttributes(
        contextState: TelemetryContextState,
        transferSnapshot: TransferSnapshot
    ) -> MobileTelemetryAttributes {
        var attributes: MobileTelemetryAttributes = [
            "app.route": .string(contextState.route.rawValue),
            "backup.flow_state": .string(contextState.pairingStatus.backupFlowState.rawValue),
            "pairing.phase": .string(contextState.pairingStatus.phase.rawValue),
            "permission.media_scope": .string(contextState.permissionSummary.mediaScope.rawValue),
            "permission.camera_granted": .bool(contextState.permissionSummary.cameraGranted),
            "permission.notifications_granted": .bool(contextState.permissionSummary.notificationsGranted),
            "permission.low_battery_warning_needed": .bool(contextState.permissionSummary.lowBatteryWarningNeeded),
            "permission.is_charging": .bool(contextState.permissionSummary.isCharging),
            "backup.remove_after_backup_enabled": .bool(contextState.removeAfterBackupEnabled),
            "app.has_paired_desktop": .bool(contextState.pairingStatus.desktopName?.isEmpty == false),
            "transfer.transferred_count": .int(transferSnapshot.transferredCount),
            "transfer.total_count": .int(transferSnapshot.totalCount),
            "transfer.failed_count": .int(transferSnapshot.failedCount)
        ]
        if let transport = contextState.pairingStatus.transport ?? transferSnapshot.activeTransportsForDisplay.first {
            attributes["transfer.transport"] = .string(transport.rawValue)
        }
        if let sessionID = contextState.pairingStatus.sessionID, !sessionID.isEmpty {
            attributes["correlation.session_id"] = .string(sessionID)
        }
        if let pendingItemCount = contextState.homeSummary.pendingItemCount {
            attributes["home.pending_item_count"] = .int(pendingItemCount)
        }
        if let desktopName = contextState.pairingStatus.desktopName, !desktopName.isEmpty {
            attributes["pairing.desktop_name_present"] = .bool(true)
            attributes["pairing.desktop_name_length"] = .int(desktopName.count)
        }
        return attributes
    }

    private func mergedTelemetryAttributes(
        extraAttributes: MobileTelemetryAttributes,
        contextState: TelemetryContextState,
        transferSnapshot: TransferSnapshot
    ) -> MobileTelemetryAttributes {
        var mergedAttributes = telemetryContextAttributes(
            contextState: contextState,
            transferSnapshot: transferSnapshot
        )
        for (key, value) in extraAttributes {
            mergedAttributes[key] = value
        }
        return mergedAttributes
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

    private func flushTelemetry() {
        let worker = sideEffectWorker
        Task.detached(priority: .utility) {
            await worker.forceFlush()
        }
    }

    private func configureMemoryWarningObservation() {
#if canImport(UIKit)
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
#endif
    }

    private func configureAppLifecycleObservation() {
#if canImport(UIKit)
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
#endif
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
        await transferService.progressSnapshot() ?? .demo
    }
}

private actor MobileAppSideEffectWorker {
    private let stateStore: AppStateStore
    private let telemetryClient: TelemetryClient

    init(stateStore: AppStateStore, telemetryClient: TelemetryClient) {
        self.stateStore = stateStore
        self.telemetryClient = telemetryClient
    }

    func persist(snapshot: LaunchSnapshot) async {
        await stateStore.saveLaunchSnapshot(snapshot)
    }

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        await telemetryClient.record(event: event, attributes: attributes)
    }

    func begin(span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) async {
        await telemetryClient.begin(span: span, attributes: attributes)
    }

    func end(
        span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    ) async {
        await telemetryClient.end(span: span, attributes: attributes, status: status)
    }

    func increment(
        metric: MobileTelemetryMetric,
        by value: Int,
        attributes: MobileTelemetryAttributes
    ) async {
        await telemetryClient.increment(metric: metric, by: value, attributes: attributes)
    }

    func forceFlush() async {
        await telemetryClient.forceFlush()
    }
}
