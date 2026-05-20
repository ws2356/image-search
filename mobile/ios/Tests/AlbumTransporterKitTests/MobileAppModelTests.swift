import XCTest
import Combine
@testable import AlbumTransporterKit

struct LaunchSnapshot: Sendable {
    var backupSession: BackupSession?

    static let firstLaunch = LaunchSnapshot(backupSession: nil)
}

protocol AppStateStore: Sendable {
    func loadLaunchSnapshot() async -> LaunchSnapshot
    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async
}

actor InMemoryAppStateStore: AppStateStore {
    private var snapshot: LaunchSnapshot

    init(snapshot: LaunchSnapshot = .firstLaunch) {
        self.snapshot = snapshot
    }

    func loadLaunchSnapshot() async -> LaunchSnapshot {
        snapshot
    }

    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async {
        self.snapshot = snapshot
    }
}

@MainActor
final class AppStateStoreBackedBackupSessionProvider: BackupSessionProviding {
    @Published private var _currentBackupSession: BackupSession?
    @Published private var _lastBackupSession: BackupSession?

    private let store: AppStateStore
    private var hasLoaded = false

    private static let terminatingStatuses: Set<MobileBackupFlowState> = [
        .transferCompleted, .transferFailed, .transferStopped,
        .pairingFailed, .pairingStopped, .pairingExpired
    ]

    init(store: AppStateStore) {
        self.store = store
    }

    var currentBackupSession: BackupSession? { _currentBackupSession }

    var currentBackupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        $_currentBackupSession.eraseToAnyPublisher()
    }

    var lastBackupSession: BackupSession? { _lastBackupSession }

    var lastBackupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        $_lastBackupSession.eraseToAnyPublisher()
    }

    func load() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        _lastBackupSession = await store.loadLaunchSnapshot().backupSession
    }

    func saveBackupSession(_ session: BackupSession?) async {
        _currentBackupSession = session
        guard let session, Self.terminatingStatuses.contains(session.status) else {
            return
        }
        _lastBackupSession = session
        let store = store
        Task(priority: .utility) {
            await store.saveLaunchSnapshot(LaunchSnapshot(backupSession: session))
        }
    }
}

extension PermissionSummary {
    init(
        cameraGranted: Bool,
        notificationsGranted: Bool,
        mediaScope: PermissionScope,
        excludedCategoryDescription: String?,
        lowBatteryWarningNeeded: Bool,
        isCharging: Bool
    ) {
        _ = cameraGranted
        _ = notificationsGranted
        _ = excludedCategoryDescription
        self.init(
            mediaScope: mediaScope,
            lowBatteryWarningNeeded: lowBatteryWarningNeeded,
            isCharging: isCharging
        )
    }
}

extension TransferSnapshot {
    init(
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int,
        skippedCount: Int = 0,
        transport: TransferTransport,
        liveTransports: [TransferTransport]? = nil,
        transferSpeedText: String? = nil,
        etaMinutes: Double?,
        statusMessage: String,
        guidanceMessage: String,
        isIncompleteLibrary: Bool
    ) {
        _ = guidanceMessage
        _ = isIncompleteLibrary
        self.init(
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            transport: transport,
            liveTransports: liveTransports,
            transferSpeedBytesPerSecond: Self.legacyTransferSpeedBytesPerSecond(from: transferSpeedText),
            etaMinutes: etaMinutes,
            phase: Self.legacyPhase(
                statusMessage: statusMessage,
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount
            ),
            failureMessage: Self.legacyFailureMessage(
                statusMessage: statusMessage,
                transferredCount: transferredCount,
                totalCount: totalCount,
                failedCount: failedCount
            )
        )
    }

    var statusMessage: String {
        switch phase {
        case .preparing:
            return "Preparing the local media backup with the paired desktop."
        case .transferring:
            let processedCount = min(transferredCount + failedCount, totalCount)
            if totalCount > 0, processedCount >= totalCount {
                return "Phone finished sending the current batch of media to the paired desktop."
            }
            return "Processed \(processedCount) of \(totalCount) items for the paired desktop."
        case .stopped:
            return totalCount == 0
                ? "Backup canceled before transfer started."
                : "Backup stopped. In-flight work was canceled to release resources quickly."
        case .completed:
            return "Desktop confirmed that this transfer session is complete."
        case .failed:
            return failureMessage ?? "Transfer failed."
        }
    }

    var guidanceMessage: String {
        switch phase {
        case .preparing:
            return "Keep the app in the foreground while the phone prepares the backup session."
        case .transferring:
            let processedCount = min(transferredCount + failedCount, totalCount)
            if totalCount > 0, processedCount >= totalCount {
                return failedCount == 0
                    ? "Backup completes automatically after the desktop confirms this transfer session."
                    : "Some items could not be transferred. Start another backup session to retry remaining items, then inspect the MobileTransfer device logs for per-item errors."
            }
            if failedCount > 0 {
                return "Some items have failed so far. Let the current run finish, then inspect the MobileTransfer device logs for per-item errors."
            }
            return "Keep the app in the foreground while the phone sends items to the desktop."
        case .stopped:
            return "Start a new backup session to continue sending any remaining accessible items."
        case .completed:
            return "You can return home and start another backup whenever new media appears on the device."
        case .failed:
            let normalizedMessage = failureMessage?.lowercased() ?? ""
            if normalizedMessage.contains("storage is full") || normalizedMessage.contains("disk space") {
                return "Free up disk space on the desktop, then start a new backup session."
            }
            if normalizedMessage.contains("no paired desktop") {
                return "Pair with the desktop again before starting a backup."
            }
            return "Retry the backup after confirming the paired desktop is reachable and ready."
        }
    }

    var isIncompleteLibrary: Bool {
        false
    }

    var transferSpeedText: String? {
        String(
            format: "%.2f MB/s",
            (transferSpeedBytesPerSecond ?? 0) / 1_048_576.0
        )
    }

    private static func legacyPhase(
        statusMessage: String,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int
    ) -> TransferPhase {
        let normalizedMessage = statusMessage.lowercased()
        if normalizedMessage.contains("desktop confirmed") {
            return .completed
        }
        if normalizedMessage.contains("finished sending") {
            return .transferring
        }
        if normalizedMessage.contains("stopped") || normalizedMessage.contains("canceled") {
            return .stopped
        }
        if normalizedMessage.contains("storage is full")
            || normalizedMessage.contains("no paired desktop")
            || normalizedMessage.contains("failed")
            || (failedCount > 0 && totalCount == 0)
        {
            return .failed
        }
        if normalizedMessage.contains("prepar") || (totalCount == 0 && transferredCount == 0) {
            return .preparing
        }
        return .transferring
    }

    private static func legacyFailureMessage(
        statusMessage: String,
        transferredCount: Int,
        totalCount: Int,
        failedCount: Int
    ) -> String? {
        switch legacyPhase(
            statusMessage: statusMessage,
            transferredCount: transferredCount,
            totalCount: totalCount,
            failedCount: failedCount
        ) {
        case .failed:
            return statusMessage
        default:
            return nil
        }
    }

    private static func legacyTransferSpeedBytesPerSecond(from text: String?) -> Double? {
        guard let text else {
            return nil
        }
        let normalizedText = text
            .replacingOccurrences(of: "MB/s", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let megabytesPerSecond = Double(normalizedText) else {
            return nil
        }
        return megabytesPerSecond * 1_048_576.0
    }
}

extension HomeViewState {
    var previouslyTransferredDescription: String? {
        previousTransferDescription
    }
}

extension CompletionViewState {
    var totalTransferredDescription: String? {
        guard let itemsBackedUp else {
            return nil
        }
        return "\(itemsBackedUp)/\(itemsBackedUp)"
    }
}

@MainActor
final class MobileAppModelTests: XCTestCase {
    private func makeModel(
        stateStore: AppStateStore,
        qrCodePayloadDecoder: QRCodePayloadDecoding,
        pairingService: PairingService,
        permissionService: PermissionService,
        transferService: TransferService,
        telemetryClient: TelemetryClient,
        telemetryService: TelemetryService? = nil,
        telemetryContextProvider: TelemetryContextProvider? = nil
    ) -> MobileAppModel {
        let resolvedTelemetryContextProvider = telemetryContextProvider ?? DefaultTelemetryContextProvider()
        let resolvedTelemetryService = telemetryService ?? DefaultTelemetryService(
            transferService: transferService,
            transportResolver: transferService,
            telemetryClient: telemetryClient,
            contextProvider: resolvedTelemetryContextProvider
        )
        let backupSessionProvider = AppStateStoreBackedBackupSessionProvider(store: stateStore)
        return MobileAppModel(
            backupSessionProvider: backupSessionProvider,
            qrCodePayloadDecoder: qrCodePayloadDecoder,
            pairingService: pairingService,
            permissionService: permissionService,
            transferService: transferService,
            telemetryService: resolvedTelemetryService,
            telemetryContextProvider: resolvedTelemetryContextProvider
        )
    }

    private func startPairing(
        model: MobileAppModel,
        qrString: String = PairingQRCodePayload.demoScanValue,
        telemetryService: TelemetryService = NoopTelemetryService()
    ) async {
        await model.showPairingPage(qrString: qrString)
        await orchestrateVisiblePairPage(model: model, telemetryService: telemetryService)
    }

    private func orchestrateVisiblePairPage(
        model: MobileAppModel,
        telemetryService: TelemetryService = NoopTelemetryService()
    ) async {
        let pairingViewModel = PairingPageViewModel(
            model: model,
            telemetryService: telemetryService,
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder()
        )
        await pairingViewModel.orchestratePairing()
    }

    private func requireErrorSummary(
        from route: AppRoute,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ErrorSummary {
        guard case .error(let summary) = route else {
            XCTFail("Expected route to be .error but got \(route)", file: file, line: line)
            return .generic
        }
        return summary
    }

    func test_transfer_snapshot_decodes_legacy_payload_without_skipped_count() throws {
        let legacyPayload = """
        {
          "transferredCount": 12,
          "totalCount": 30,
          "failedCount": 1,
          "transport": "lan",
          "etaDescription": "17 min remaining",
          "statusMessage": "Legacy transfer snapshot",
          "guidanceMessage": "Keep app in foreground.",
          "isIncompleteLibrary": false
        }
        """
        let decodedSnapshot = try JSONDecoder().decode(
            TransferSnapshot.self,
            from: Data(legacyPayload.utf8)
        )

        XCTAssertEqual(decodedSnapshot.skippedCount, 0)
        XCTAssertNil(decodedSnapshot.etaMinutes)
    }

    func test_load_routes_to_home_for_first_launch() async {
        let store = InMemoryAppStateStore(snapshot: .firstLaunch)
        let model = makeModel(
            stateStore: store,
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()

        XCTAssertEqual(model.route, .home)
    }

    func test_load_records_diagnostic_checkpoint_with_persisted_backup_session() async {
        let telemetryClient = RecordingTelemetryClient()
        let store = InMemoryAppStateStore(
            snapshot: LaunchSnapshot(
                backupSession: BackupSession(
                    sessionID: "session-123",
                    desktopName: "Studio Mac",
                    status: .transferCompleted,
                    updatedAt: Date(timeIntervalSince1970: 1_776_123_610)
                )
            )
        )
        let model = makeModel(
            stateStore: store,
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: telemetryClient
        )

        await model.load()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let diagnosticRecord = await telemetryClient.latestRecord(for: .diagnosticCheckpoint)
        XCTAssertEqual(diagnosticRecord?.attributes["diagnostic.area"], .string("app_load_completed"))
        XCTAssertEqual(diagnosticRecord?.attributes["backup.session_present"], .bool(true))
        XCTAssertEqual(diagnosticRecord?.attributes["backup.session_status"], .string("transferCompleted"))
        XCTAssertEqual(diagnosticRecord?.attributes["backup.session_id_present"], .bool(true))
    }

    func test_load_does_not_trigger_transfer_recovery_while_idle() async {
        let transferService = ForegroundRecoveryTrackingTransferService()
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let recoveryCallCount = await transferService.foregroundRecoveryCallCount()
        XCTAssertEqual(recoveryCallCount, 0)
    }

    func test_error_page_result_success_restarts_scan_and_cancel_returns_home() async {
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        let scanFailureResult = ScanningPageResult(result: .failure(.scannerFailed))
        await model.onScanningCompleted(with: scanFailureResult)
        _ = requireErrorSummary(from: model.route)

        let errorRetryResult = ErrorPageResult(result: .success(()))
        await model.onErrorCompleted(with: errorRetryResult)
        XCTAssertEqual(model.route, .scan)

        let scanFailureResult2 = ScanningPageResult(result: .failure(.scannerFailed))
        await model.onScanningCompleted(with: scanFailureResult2)
        _ = requireErrorSummary(from: model.route)

        let errorCancelResult = ErrorPageResult(result: .failure(.unknown))
        await model.onErrorCompleted(with: errorCancelResult)
        XCTAssertEqual(model.route, .home)
    }

    func test_start_backup_shows_low_battery_alert_when_needed() async {
        let lowBatteryFullAccess = PermissionSummary(
            cameraGranted: true,
            notificationsGranted: true,
            mediaScope: .full,
            excludedCategoryDescription: nil,
            lowBatteryWarningNeeded: true,
            isCharging: false
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: lowBatteryFullAccess),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()

        XCTAssertEqual(model.route, .permissions)
        XCTAssertTrue(permissionsViewModel.isShowingLowBatteryWarning)
    }

    func test_begin_pairing_shows_error_when_desktop_stops_pairing() async {
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StoppedPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)

        _ = requireErrorSummary(from: model.route)
        XCTAssertEqual(model.backupSessionProvider.currentBackupSession?.status, .pairingStopped)
    }

    func test_start_backup_shows_full_media_access_reminder_before_continuing() async {
        let limitedAccessSummary = PermissionSummary(
            cameraGranted: true,
            notificationsGranted: true,
            mediaScope: .limited,
            excludedCategoryDescription: "Only selected items are currently granted by iOS.",
            lowBatteryWarningNeeded: false,
            isCharging: true
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: limitedAccessSummary),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()

        XCTAssertEqual(model.route, .permissions)
        XCTAssertTrue(permissionsViewModel.isShowingMediaAccessAlert)
        XCTAssertFalse(permissionsViewModel.mediaAccessAlertMessage.isEmpty)

        await permissionsViewModel.continueBackupFromMediaAccessNotNow()
        XCTAssertTrue(permissionsViewModel.isShowingRemoveAfterBackupPrompt)
        await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService,
            pollingIntervalNanoseconds: 10_000_000
        )
        await transferViewModel.orchestrateTransfer()
        XCTAssertEqual(model.route, .completed)
    }

    func test_start_backup_stages_initial_transfer_snapshot_before_orchestration_runs() async {
        let telemetryClient = RecordingTelemetryClient()
        let transferService = StopTrackingTransferService()
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: telemetryClient
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.route, .transfer)
        XCTAssertEqual(model.backupFlowState, .transferInProgress)
        let stagedSnapshot = await transferService.progressSnapshot()
        XCTAssertNotNil(stagedSnapshot)
        XCTAssertEqual(stagedSnapshot?.transport, .lan)

        let transferStartedRecord = await telemetryClient.latestRecord(for: .transferStarted)
        XCTAssertEqual(
            transferStartedRecord?.attributes["transfer.is_incomplete_library"],
            .bool(false)
        )
        XCTAssertEqual(
            transferStartedRecord?.attributes["transfer.remove_after_backup_enabled"],
            .bool(false)
        )
    }

    func test_low_battery_not_now_returns_home_without_stopping_transfer_service() async {
        let lowBatteryFullAccess = PermissionSummary(
            cameraGranted: true,
            notificationsGranted: false,
            mediaScope: .full,
            excludedCategoryDescription: nil,
            lowBatteryWarningNeeded: true,
            isCharging: false
        )
        let telemetryClient = RecordingTelemetryClient()
        let transferService = StopTrackingTransferService()
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: lowBatteryFullAccess),
            transferService: transferService,
            telemetryClient: telemetryClient
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        XCTAssertTrue(permissionsViewModel.isShowingLowBatteryWarning)

        await permissionsViewModel.cancelFromLowBattery()

        XCTAssertEqual(model.route, .home)
        XCTAssertEqual(model.backupFlowState, .transferStopped)
        let stopCallCount = await transferService.stopCallCount()
        XCTAssertEqual(stopCallCount, 0)
        let stagedSnapshot = await transferService.progressSnapshot()
        XCTAssertNotNil(stagedSnapshot)
        XCTAssertEqual(stagedSnapshot?.transport, .lan)
        var stopReasonAttribute: MobileTelemetryAttributeValue?
        for _ in 0..<20 {
            let stopRecord = await telemetryClient.latestRecord(for: .transferStopped)
            stopReasonAttribute = stopRecord?.attributes["transfer.stop_reason"]
            if stopReasonAttribute != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(stopReasonAttribute, .string("low_battery_declined"))
    }

    func test_stop_transfer_returns_home_without_interrupted_page() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 2,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Processed 2 of 5 items for the paired desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: PollingTransferService(
                inFlightSnapshot: inFlightSnapshot,
                finalSnapshot: finalSnapshot
            ),
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)

        let transferTask = Task {
            await permissionsViewModel.startPreflight()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService,
            pollingIntervalNanoseconds: 10_000_000
        )
        transferViewModel.requestStopTransfer()
        await transferViewModel.confirmStopTransfer()

        XCTAssertEqual(model.route, .home)
        XCTAssertFalse(transferViewModel.isShowingStopConfirmation)
        let homeViewModel = HomePageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService
        )
        await homeViewModel.refreshSummary()
        XCTAssertNotNil(homeViewModel.summary.lastBackupDescription)
        XCTAssertNotNil(homeViewModel.summary.previouslyTransferredDescription)

        await transferTask.value
        XCTAssertEqual(model.route, .home)
    }

    func test_start_backup_polls_transfer_progress_while_session_is_running() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 2,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Processed 2 of 5 items for the paired desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: PollingTransferService(
                inFlightSnapshot: inFlightSnapshot,
                finalSnapshot: finalSnapshot
            ),
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)

        let transferTask = Task {
            await permissionsViewModel.startPreflight()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(permissionsViewModel.isShowingRemoveAfterBackupPrompt)
        await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService
        )
        let orchestrationTask = Task {
            await transferViewModel.orchestrateTransfer()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(model.route == .transfer || model.route == .completed)
        XCTAssertEqual(transferViewModel.snapshot.totalCount, 5)
        XCTAssertGreaterThanOrEqual(transferViewModel.snapshot.transferredCount, 2)

        await transferTask.value
        await orchestrationTask.value
        XCTAssertEqual(model.route, .completed)
        let completedSnapshot = await model.transferService.progressSnapshot()
        XCTAssertEqual(completedSnapshot?.transferredCount, 5)
        let completionViewModel = CompletionPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )
        await completionViewModel.reloadSummary()
        let completionSummary = completionViewModel.summary
        XCTAssertEqual(completionSummary.itemsBackedUp, 5)
        XCTAssertEqual(completionSummary.totalTransferredDescription, "5/5")
        XCTAssertNotNil(completionSummary.durationDescription)
        XCTAssertNotNil(completionSummary.completedAtDescription)
    }

    func test_start_backup_updates_transfer_snapshot_from_progress_callback() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 4,
            totalCount: 10,
            failedCount: 0,
            transport: .lan,
            etaMinutes: 3,
            statusMessage: "Sending media to desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 10,
            totalCount: 10,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: CallbackOnlyTransferService(
                inFlightSnapshot: inFlightSnapshot,
                finalSnapshot: finalSnapshot
            ),
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService
        )
        let orchestrationTask = Task {
            await transferViewModel.orchestrateTransfer()
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(transferViewModel.snapshot.totalCount, 10)
        XCTAssertGreaterThanOrEqual(transferViewModel.snapshot.transferredCount, 4)

        await orchestrationTask.value
        XCTAssertEqual(model.route, .completed)
        let completedSnapshot = await model.transferService.progressSnapshot()
        XCTAssertEqual(completedSnapshot?.transferredCount, 10)
    }

    func test_qr_payload_decoder_uses_url_query_format() {
        let decoder = URLQueryQRCodePayloadDecoder()
        let result = decoder.decode(scannedValue: "https://dl.boldman.net?v=2&ept=desktop.local:38933,192.168.50.17:38933&sid=pairing-demo-123&opt=482913&usp=50211")

        guard case .success(let decoded) = result else {
            return XCTFail("Expected successful payload decoding")
        }

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.endpointTargets, ["desktop.local:38933", "192.168.50.17:38933"])
        XCTAssertEqual(decoded.sessionID, "pairing-demo-123")
        XCTAssertEqual(decoded.oneTimePasscode, "482913")
        XCTAssertEqual(decoded.suggestedUSBPort, 50211)
        XCTAssertEqual(
            decoded.bootstrapURLs.map(\.absoluteString),
            [
                "http://desktop.local:38933/api/mobile/pairing/claim",
                "http://192.168.50.17:38933/api/mobile/pairing/claim",
            ]
        )
    }

    func test_qr_payload_decoder_keeps_v1_backward_compatibility() {
        let decoder = URLQueryQRCodePayloadDecoder()
        let result = decoder.decode(
            scannedValue: "https://dl.boldman.net?v=1&ept=desktop.local:38933&sid=pairing-demo-legacy&opt=123456"
        )

        guard case .success(let decoded) = result else {
            return XCTFail("Expected successful payload decoding for v1 payload")
        }

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.endpointTargets, ["desktop.local:38933"])
        XCTAssertEqual(decoded.sessionID, "pairing-demo-legacy")
        XCTAssertEqual(decoded.oneTimePasscode, "123456")
        XCTAssertNil(decoded.suggestedUSBPort)
    }

    func test_handle_incoming_universal_link_routes_to_permissions_after_pairing() async {
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.handleIncomingUniversalLink(URL(string: PairingQRCodePayload.demoScanValue)!)
        await orchestrateVisiblePairPage(model: model)

        XCTAssertEqual(model.route, .permissions)
        XCTAssertEqual(model.backupSessionProvider.currentBackupSession?.sessionID, PairingQRCodePayload.demo.sessionID)
    }

    func test_handle_incoming_universal_link_with_invalid_payload_shows_pairing_failure() async {
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.handleIncomingUniversalLink(URL(string: "https://dl.boldman.net?sid=missing-fields")!)
        await orchestrateVisiblePairPage(model: model)

        let errorSummary = requireErrorSummary(from: model.route)
        XCTAssertEqual(errorSummary.title, PairingError.decoding(message: "").title)
        XCTAssertEqual(errorSummary.message, QRCodePayloadDecoderError.missingField("v").message)
    }

    func test_handle_incoming_universal_link_prompts_before_replacing_active_transfer() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 1,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Sending items to desktop.",
            guidanceMessage: "Keep app in foreground.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Completed transfer.",
            guidanceMessage: "Done.",
            isIncompleteLibrary: false
        )
        let transferService = DelayedTransferService(
            inFlightSnapshot: inFlightSnapshot,
            finalSnapshot: finalSnapshot,
            transferDurationNanoseconds: 500_000_000
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        let transferTask = Task {
            await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        }
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(model.route, .transfer)

        await model.handleIncomingUniversalLink(URL(string: PairingQRCodePayload.demoScanValue)!)

        XCTAssertTrue(model.isShowingIncomingLinkReplacementConfirmation)
        model.cancelIncomingUniversalLinkReplacement()
        XCTAssertFalse(model.isShowingIncomingLinkReplacementConfirmation)
        XCTAssertEqual(model.route, .transfer)

        await transferTask.value
    }

    func test_confirm_incoming_universal_link_replacement_stops_transfer_and_starts_new_pairing() async {
        let telemetryClient = RecordingTelemetryClient()
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 1,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Sending items to desktop.",
            guidanceMessage: "Keep app in foreground.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Completed transfer.",
            guidanceMessage: "Done.",
            isIncompleteLibrary: false
        )
        let transferService = DelayedTransferService(
            inFlightSnapshot: inFlightSnapshot,
            finalSnapshot: finalSnapshot,
            transferDurationNanoseconds: 500_000_000
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: telemetryClient
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        let transferTask = Task {
            await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        }
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(model.route, .transfer)

        let replacementLink = "https://dl.boldman.net?v=2&ept=desktop.local:38933&sid=pairing-replacement-001&opt=456123&usp=50211"
        await model.handleIncomingUniversalLink(URL(string: replacementLink)!)
        XCTAssertTrue(model.isShowingIncomingLinkReplacementConfirmation)

        await model.confirmIncomingUniversalLinkReplacement()
        if case .pair(let qrString) = model.route {
            XCTAssertEqual(qrString, replacementLink)
        } else {
            XCTFail("Expected route to be .pair but got \(model.route)")
        }
        await orchestrateVisiblePairPage(model: model)

        XCTAssertFalse(model.isShowingIncomingLinkReplacementConfirmation)
        XCTAssertEqual(model.route, .permissions)
        XCTAssertEqual(model.backupSessionProvider.currentBackupSession?.sessionID, "pairing-replacement-001")
        let stopCallCount = await transferService.stopCallCount()
        XCTAssertEqual(stopCallCount, 1)
        var stopReasonAttribute: MobileTelemetryAttributeValue?
        for _ in 0..<20 {
            let stopRecord = await telemetryClient.latestRecord(for: .transferStopped)
            stopReasonAttribute = stopRecord?.attributes["transfer.stop_reason"]
            if stopReasonAttribute != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(stopReasonAttribute, .string("replaced_by_universal_link"))

        await transferTask.value
    }

    func test_open_scan_flow_returns_without_waiting_for_slow_side_effect_io() async {
        let model = makeModel(
            stateStore: SlowAppStateStore(saveDelayNanoseconds: 600_000_000),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: SlowTelemetryClient(recordDelayNanoseconds: 600_000_000)
        )
        let start = Date()

        await model.openScanFlow()

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(model.route, .scan)
        XCTAssertLessThan(elapsed, 0.25)
    }

    func test_handle_app_did_become_active_does_not_trigger_transfer_recovery_while_idle() async {
        let transferService = ForegroundRecoveryTrackingTransferService()
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )

        await model.handleAppDidBecomeActive()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let recoveryCallCount = await transferService.foregroundRecoveryCallCount()
        XCTAssertEqual(recoveryCallCount, 0)
    }

    func test_complete_transfer_moves_assets_to_recently_removed_when_enabled() async {
        let completedSnapshot = TransferSnapshot(
            transferredCount: 3,
            totalCount: 3,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let transferService = CleanupTrackingTransferService(completedSnapshot: completedSnapshot)
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        XCTAssertTrue(permissionsViewModel.isShowingRemoveAfterBackupPrompt)
        await permissionsViewModel.selectRemoveAfterBackupPreference(true)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService
        )
        await transferViewModel.orchestrateTransfer()

        let cleanupCallCount = await transferService.cleanupCallCount()
        XCTAssertEqual(cleanupCallCount, 1)
        let completionViewModel = CompletionPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )
        await completionViewModel.reloadSummary()
        let completionSummary = completionViewModel.summary
        XCTAssertTrue(completionSummary.message.contains("Moved 3 transferred items to Recently Removed"))
    }

    func test_complete_transfer_with_failures_keeps_completion_route_and_reports_failed_flow() async {
        let completedSnapshot = TransferSnapshot(
            transferredCount: 2,
            totalCount: 3,
            failedCount: 1,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let telemetryClient = RecordingTelemetryClient()
        let transferService = CleanupTrackingTransferService(completedSnapshot: completedSnapshot)
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: telemetryClient
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        await permissionsViewModel.startPreflight()
        await permissionsViewModel.selectRemoveAfterBackupPreference(false)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: NoopTelemetryService(),
            transportResolver: model.transferService
        )
        await transferViewModel.orchestrateTransfer()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.route, .completed)
        XCTAssertEqual(model.backupFlowState, .transferFailed)
        let completionRecord = await telemetryClient.latestRecord(for: .transferCompleted)
        XCTAssertEqual(
            completionRecord?.attributes["transfer.failed_count"],
            .int(1)
        )
    }

    func test_begin_pairing_records_invalid_qr_failure_reason() async {
        let telemetryClient = RecordingTelemetryClient()
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: FailingQRCodePayloadDecoder(error: .invalidURL),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: telemetryClient
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model, qrString: "not-a-valid-payload")
        try? await Task.sleep(nanoseconds: 50_000_000)

        let failureRecord = await telemetryClient.latestRecord(for: .pairingFailed)
        XCTAssertEqual(
            failureRecord?.attributes["pairing.failure_reason"],
            .string(QRCodePayloadDecoderError.invalidHost.title)
        )
        XCTAssertEqual(
            failureRecord?.attributes["pairing.failure_message"],
            .string(QRCodePayloadDecoderError.invalidHost.message)
        )
        XCTAssertEqual(
            failureRecord?.attributes["app.route"],
            .string("pair")
        )
        XCTAssertEqual(model.backupFlowState, .pairingFailed)
        XCTAssertEqual(model.backupSessionProvider.currentBackupSession?.status, .pairingFailed)
    }

    func test_invalid_qr_code_navigates_to_error_page() async {
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: FailingQRCodePayloadDecoder(error: .invalidURL),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model, qrString: "invalid-qr-code")
        try? await Task.sleep(nanoseconds: 50_000_000)

        let errorSummary = requireErrorSummary(from: model.route)
        XCTAssertEqual(errorSummary.title, QRCodePayloadDecoderError.invalidHost.title)
        XCTAssertEqual(errorSummary.message, QRCodePayloadDecoderError.invalidHost.message)
    }

    func test_begin_pairing_records_pairing_failed_when_service_does_not_complete_pairing() async {
        let telemetryClient = RecordingTelemetryClient()
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: UnexpectedPhasePairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: StaticTransferService(),
            telemetryClient: telemetryClient
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model)
        try? await Task.sleep(nanoseconds: 50_000_000)

        if case .error(_) = model.route {
            XCTAssertNil(model.backupSessionProvider.currentBackupSession?.sessionID)
        } else {
            XCTFail("Expected route to be .error but got \(model.route)")
        }
        XCTAssertEqual(model.backupFlowState, .pairingFailed)
        XCTAssertEqual(model.backupSessionProvider.currentBackupSession?.status, .pairingFailed)
        let failureRecord = await telemetryClient.latestRecord(for: .pairingFailed)
        XCTAssertEqual(
            failureRecord?.attributes["pairing.failure_reason"],
            .string("Pairing Failed")
        )
    }

    func test_start_backup_records_preflight_and_completion_telemetry_context() async {
        let completedSnapshot = TransferSnapshot(
            transferredCount: 3,
            totalCount: 3,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let telemetryClient = RecordingTelemetryClient()
        let transferService = CleanupTrackingTransferService(completedSnapshot: completedSnapshot)
        let telemetryContextProvider = DefaultTelemetryContextProvider()
        let telemetryService = DefaultTelemetryService(
            transferService: transferService,
            transportResolver: transferService,
            telemetryClient: telemetryClient,
            contextProvider: telemetryContextProvider
        )
        let model = makeModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: telemetryClient,
            telemetryService: telemetryService,
            telemetryContextProvider: telemetryContextProvider
        )
        let permissionsViewModel = PermissionsPageViewModel(
            model: model,
            telemetryService: telemetryService
        )

        await model.load()
        await model.openScanFlow()
        await startPairing(model: model, telemetryService: telemetryService)
        await permissionsViewModel.startPreflight()
        await permissionsViewModel.selectRemoveAfterBackupPreference(true)
        let transferViewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )
        await transferViewModel.orchestrateTransfer()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let preflightRecord = await telemetryClient.latestRecord(for: .backupPreflightStarted)
        XCTAssertEqual(
            preflightRecord?.attributes["permission.media_scope"],
            .string(PermissionScope.full.rawValue)
        )
        XCTAssertEqual(
            preflightRecord?.attributes["app.route"],
            .string("permissions")
        )

        let completionRecord = await telemetryClient.latestRecord(for: .transferCompleted)
        XCTAssertEqual(
            completionRecord?.attributes["transfer.cleanup_result"],
            .string("removed")
        )
        XCTAssertEqual(
            completionRecord?.attributes["transfer.cleanup_removed_count"],
            .int(3)
        )
        XCTAssertEqual(
            completionRecord?.attributes["transfer.total_count"],
            .int(3)
        )
        XCTAssertEqual(
            completionRecord?.attributes["transfer.transport"],
            .string(TransferTransport.lan.rawValue)
        )
        let removePreferenceRecord = await telemetryClient.latestRecord(for: .removeAfterBackupPreferenceSelected)
        XCTAssertEqual(
            removePreferenceRecord?.attributes["backup.remove_after_backup_enabled"],
            .bool(true)
        )
        XCTAssertEqual(
            removePreferenceRecord?.attributes["correlation.session_id"],
            .string("pairing-demo-001")
        )
    }
}

private struct StaticPairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> Result<PairingResponse, PairingError> {
        .success(
            PairingResponse(
                sessionID: payload.sessionID,
                desktopName: "Studio Mac",
                transport: .lan
            )
        )
    }
}

private struct StoppedPairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> Result<PairingResponse, PairingError> {
        _ = payload
        return .failure(.rejected(message: "Desktop canceled this pairing request."))
    }
}

private struct UnexpectedPhasePairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> Result<PairingResponse, PairingError> {
        _ = payload
        return .failure(.transport(message: "Unexpected pairing state."))
    }
}

private struct StaticQRCodePayloadDecoder: QRCodePayloadDecoding {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        .success(.demo)
    }
}

private struct FailingQRCodePayloadDecoder: QRCodePayloadDecoding {
    let error: QRCodePayloadDecoderError

    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        .failure(error)
    }
}

private actor StaticPermissionService: PermissionService {
    let summary: PermissionSummary
    private var isRemoveAfterBackupEnabled = false

    init(summary: PermissionSummary) {
        self.summary = summary
    }

    func loadPermissionSummary() async -> PermissionSummary {
        summary
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
    }
}

@MainActor
private final class NoopTelemetryService: TelemetryService {
    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {}
    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) {}
    func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    ) {}
    func incrementTelemetryMetric(_ metric: MobileTelemetryMetric, by value: Int, attributes: MobileTelemetryAttributes) {}
    func beginBackupSessionTelemetry() {}
    func recordDialogView(name: String) {}
    func recordInteraction(name: String, location: String) {}
    func forceFlush() {}
}

private struct StaticTransferService: TransferService {
    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(.demo)
        return .demo
    }

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        .demo
    }

    func progressSnapshot() async -> TransferSnapshot? {
        .demo
    }

    func transferCompletionState() async -> TransferCompletionState? {
        nil
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}

private actor RecordingTelemetryClient: TelemetryClient {
    private var records: [RecordedTelemetry] = []

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        records.append(
            RecordedTelemetry(
                event: event,
                attributes: attributes
            )
        )
    }

    func latestRecord(for event: MobileTelemetryEvent) -> RecordedTelemetry? {
        records.last(where: { $0.event == event })
    }
}

private actor PollingTransferService: TransferService {
    private let inFlightSnapshot: TransferSnapshot
    private let finalSnapshot: TransferSnapshot
    private var currentSnapshotValue: TransferSnapshot?
    private var completionState: TransferCompletionState?

    init(inFlightSnapshot: TransferSnapshot, finalSnapshot: TransferSnapshot) {
        self.inFlightSnapshot = inFlightSnapshot
        self.finalSnapshot = finalSnapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        currentSnapshotValue = inFlightSnapshot
        try? await Task.sleep(nanoseconds: 80_000_000)
        currentSnapshotValue = finalSnapshot
        return finalSnapshot
    }

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        currentSnapshotValue ?? finalSnapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        currentSnapshotValue
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}

private actor CleanupTrackingTransferService: TransferService {
    private let completedSnapshot: TransferSnapshot
    private var cleanupCalls = 0
    private var snapshot: TransferSnapshot?
    private var completionState: TransferCompletionState?

    init(completedSnapshot: TransferSnapshot) {
        self.completedSnapshot = completedSnapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        snapshot = completedSnapshot
        progress(completedSnapshot)
        return completedSnapshot
    }

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        let resolvedSnapshot = snapshot ?? self.completedSnapshot
        snapshot = resolvedSnapshot
        completionState = TransferCompletionState(
            snapshot: resolvedSnapshot,
            cleanupResult: .skipped,
            completedAt: Date(),
            sessionDuration: 1
        )
        return resolvedSnapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot ?? completedSnapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        cleanupCalls += 1
        let cleanupResult: TransferAssetCleanupResult = .removed(completedSnapshot.transferredCount)
        if let completionState {
            self.completionState = TransferCompletionState(
                snapshot: completionState.snapshot,
                cleanupResult: cleanupResult,
                completedAt: completionState.completedAt,
                sessionDuration: completionState.sessionDuration
            )
        }
        return cleanupResult
    }

    func cleanupCallCount() -> Int {
        cleanupCalls
    }
}

private actor CallbackOnlyTransferService: TransferService {
    private let inFlightSnapshot: TransferSnapshot
    private let finalSnapshot: TransferSnapshot
    private var currentSnapshotValue: TransferSnapshot?
    private var completionState: TransferCompletionState?

    init(inFlightSnapshot: TransferSnapshot, finalSnapshot: TransferSnapshot) {
        self.inFlightSnapshot = inFlightSnapshot
        self.finalSnapshot = finalSnapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        currentSnapshotValue = inFlightSnapshot
        progress(inFlightSnapshot)
        try? await Task.sleep(nanoseconds: 120_000_000)
        currentSnapshotValue = finalSnapshot
        progress(finalSnapshot)
        return finalSnapshot
    }

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        currentSnapshotValue ?? finalSnapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        currentSnapshotValue
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}

private actor StopTrackingTransferService: TransferService {
    private var stopCalls = 0
    private var snapshot: TransferSnapshot = .demo
    private var completionState: TransferCompletionState?

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(snapshot)
        return snapshot
    }

    func stopTransfer() async -> InterruptionReason {
        stopCalls += 1
        return .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        snapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func stopCallCount() -> Int {
        stopCalls
    }
}

private actor ForegroundRecoveryTrackingTransferService: TransferService {
    private var foregroundRecoveryCalls = 0
    private var snapshot: TransferSnapshot = .demo
    private var completionState: TransferCompletionState?

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(snapshot)
        return snapshot
    }

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        snapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func handleAppDidBecomeActive() async {
        foregroundRecoveryCalls += 1
    }

    func foregroundRecoveryCallCount() -> Int {
        foregroundRecoveryCalls
    }
}

private actor DelayedTransferService: TransferService {
    private let inFlightSnapshot: TransferSnapshot
    private let finalSnapshot: TransferSnapshot
    private let transferDurationNanoseconds: UInt64
    private var stopCalls = 0
    private var snapshot: TransferSnapshot?
    private var completionState: TransferCompletionState?

    init(
        inFlightSnapshot: TransferSnapshot,
        finalSnapshot: TransferSnapshot,
        transferDurationNanoseconds: UInt64
    ) {
        self.inFlightSnapshot = inFlightSnapshot
        self.finalSnapshot = finalSnapshot
        self.transferDurationNanoseconds = transferDurationNanoseconds
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        snapshot = inFlightSnapshot
        progress(inFlightSnapshot)
        try? await Task.sleep(nanoseconds: transferDurationNanoseconds)
        snapshot = finalSnapshot
        return finalSnapshot
    }

    func stopTransfer() async -> InterruptionReason {
        stopCalls += 1
        return .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        snapshot ?? finalSnapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func stopCallCount() -> Int {
        stopCalls
    }
}

private actor SlowAppStateStore: AppStateStore {
    private let snapshot: LaunchSnapshot
    private let saveDelayNanoseconds: UInt64

    init(snapshot: LaunchSnapshot = .firstLaunch, saveDelayNanoseconds: UInt64) {
        self.snapshot = snapshot
        self.saveDelayNanoseconds = saveDelayNanoseconds
    }

    func loadLaunchSnapshot() async -> LaunchSnapshot {
        snapshot
    }

    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async {
        try? await Task.sleep(nanoseconds: saveDelayNanoseconds)
    }
}

private actor SlowTelemetryClient: TelemetryClient {
    private let recordDelayNanoseconds: UInt64

    init(recordDelayNanoseconds: UInt64) {
        self.recordDelayNanoseconds = recordDelayNanoseconds
    }

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        _ = attributes
        try? await Task.sleep(nanoseconds: recordDelayNanoseconds)
    }
}

private struct RecordedTelemetry: Equatable {
    let event: MobileTelemetryEvent
    let attributes: MobileTelemetryAttributes
}
