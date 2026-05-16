import SwiftUI

/// Prompt media access update -> Prompt if low battery -> Prompt if remove after backup

@MainActor
final class PermissionsPageViewModel: ObservableObject {
    private enum PreflightPhase: Equatable {
        case idle
        case promptingMediaAccess
        case promptingLowBattery
        case promptingRemoveAfterBackup
    }

    private let model: any PermissionsPageModeling
    private let telemetryService: TelemetryService

    @Published private(set) var summary: PermissionSummary = .demo
    @Published var isShowingLowBatteryWarning = false
    @Published var isShowingMediaAccessAlert = false
    @Published var isShowingRemoveAfterBackupPrompt = false
    @Published var mediaAccessAlertMessage = "Do you want to expand access permission to back up more or all media files in your photo library?"

    private var preflightPhase: PreflightPhase = .idle
    private var isRunningPermissionsPreflight = false

    init(model: any PermissionsPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    func startPreflight() async {
        guard !isRunningPermissionsPreflight else {
            return
        }
        isRunningPermissionsPreflight = true
        resetPromptState()

        let permissionSummary = await model.permissionService.loadPermissionSummary()
        summary = permissionSummary
        telemetryService.beginTelemetrySpan(.backupPreflight, attributes: [:])
        telemetryService.recordTelemetry(
            .backupPreflightStarted,
            attributes: [
                "permission.media_scope": .string(permissionSummary.mediaScope.rawValue)
            ]
        )
        telemetryService.recordInteraction(name: "start_backup_tapped", location: "permissions")

        guard permissionSummary.mediaScope == .full else {
            preflightPhase = .promptingMediaAccess
            isShowingMediaAccessAlert = true
            telemetryService.recordTelemetry(.mediaAccessPromptShown, attributes: [:])
            return
        }

        await continueBackupPreflight()
    }

    func goBack() async {
        resetPromptState()
        let result = PermissionsPageResult(result: .failure(.permissionsCancelled))
        await model.onPermissionsCompleted(with: result)
    }

    func recordLowBatteryDialogPresented() {
        telemetryService.recordDialogView(name: "low_battery_warning")
    }

    func recordMediaAccessDialogPresented() {
        telemetryService.recordDialogView(name: "media_access_alert")
    }

    func recordRemoveAfterBackupDialogPresented() {
        telemetryService.recordDialogView(name: "remove_after_backup_prompt")
    }

    func continuePastLowBattery() async {
        guard preflightPhase == .promptingLowBattery else {
            return
        }
        preflightPhase = .idle
        isShowingLowBatteryWarning = false
        telemetryService.recordInteraction(name: "continue_anyway_tapped", location: "low_battery_warning")
        telemetryService.recordTelemetry(.lowBatteryContinued, attributes: [:])
        presentRemoveAfterBackupPrompt()
    }

    func cancelFromLowBattery() async {
        guard preflightPhase == .promptingLowBattery else {
            return
        }
        preflightPhase = .idle
        isShowingLowBatteryWarning = false
        telemetryService.recordInteraction(name: "not_now_tapped", location: "low_battery_warning")
        telemetryService.recordTelemetry(.lowBatteryCanceled, attributes: [:])
        resetPromptState()
        let result = PermissionsPageResult(result: .failure(.lowBatteryDeclined))
        await model.onPermissionsCompleted(with: result)
    }

    func updateMediaAccessTapped() {
        telemetryService.recordInteraction(name: "update_media_access_tapped", location: "media_access_alert")
    }

    func continueAfterMediaAccessUpdate() async {
        await continueBackupFromMediaAccess()
    }

    func requestMediaAccessAndContinue() async {
        _ = await model.permissionService.requestMediaAccess()
        await continueBackupFromMediaAccess()
    }

    func continueBackupFromMediaAccessNotNow() async {
        telemetryService.recordInteraction(name: "not_now_tapped", location: "media_access_alert")
        await continueBackupFromMediaAccess()
    }

    func selectRemoveAfterBackupPreference(_ shouldRemove: Bool) async {
        guard preflightPhase == .promptingRemoveAfterBackup else {
            return
        }
        preflightPhase = .idle
        isShowingRemoveAfterBackupPrompt = false
        await model.permissionService.setRemoveAfterBackupEnabled(shouldRemove)
        telemetryService.recordInteraction(
            name: shouldRemove ? "remove_after_backup_selected" : "keep_originals_selected",
            location: "remove_after_backup_prompt"
        )
        telemetryService.recordTelemetry(
            .removeAfterBackupPreferenceSelected,
            attributes: [
                "backup.remove_after_backup_enabled": .bool(shouldRemove)
            ]
        )
        isRunningPermissionsPreflight = false
        await model.handleResultForPage(
            .permissions,
            result: .success,
            target: shouldRemove ? .removeTransferredMedia : .keepOriginals
        )
    }

    private func continueBackupFromMediaAccess() async {
        guard preflightPhase == .promptingMediaAccess else {
            return
        }
        preflightPhase = .idle
        isShowingMediaAccessAlert = false
        telemetryService.recordTelemetry(.mediaAccessContinued, attributes: [:])
        summary = await model.permissionService.loadPermissionSummary()
        await continueBackupPreflight()
    }

    private func continueBackupPreflight() async {
        if summary.lowBatteryWarningNeeded && !summary.isCharging {
            preflightPhase = .promptingLowBattery
            isShowingLowBatteryWarning = true
            telemetryService.recordTelemetry(.lowBatteryPromptShown, attributes: [:])
            return
        }

        presentRemoveAfterBackupPrompt()
    }

    private func presentRemoveAfterBackupPrompt() {
        preflightPhase = .promptingRemoveAfterBackup
        isShowingRemoveAfterBackupPrompt = true
        telemetryService.recordTelemetry(.removeAfterBackupPromptShown, attributes: [:])
    }

    private func resetPromptState() {
        preflightPhase = .idle
        isShowingMediaAccessAlert = false
        isShowingLowBatteryWarning = false
        isShowingRemoveAfterBackupPrompt = false
    }

}
