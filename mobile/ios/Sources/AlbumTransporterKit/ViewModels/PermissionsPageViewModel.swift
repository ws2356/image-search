import SwiftUI

/// Prompt media access update -> Prompt if low battery -> Prompt if remove after backup

@MainActor
final class PermissionsPageViewModel: ObservableObject {
    private let model: any PermissionsPageModeling
    private let telemetryService: TelemetryService

    @Published var isShowingLowBatteryWarning = false
    @Published var isShowingMediaAccessAlert = false
    @Published var isShowingRemoveAfterBackupPrompt = false
    @Published var mediaAccessAlertMessage = "Do you want to expand access permission to back up more or all media files in your photo library?"

    private var isAwaitingMediaAccessDecision = false
    private var isAwaitingLowBatteryDecision = false
    private var isAwaitingRemoveAfterBackupDecision = false
    private var isRunningPermissionsPreflight = false

    init(model: any PermissionsPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    var summary: PermissionSummary {
        model.permissionSummary
    }

    func startPreflight() async {
        guard !isRunningPermissionsPreflight else {
            return
        }
        isRunningPermissionsPreflight = true
        resetPromptState()

        let permissionSummary = await model.permissionService.loadPermissionSummary()
        model.permissionSummary = permissionSummary
        telemetryService.beginTelemetrySpan(.backupPreflight, attributes: [:])
        telemetryService.recordTelemetry(.backupPreflightStarted, attributes: [:])
        telemetryService.recordInteraction(name: "start_backup_tapped", location: "permissions")

        guard permissionSummary.mediaScope == .full else {
            isShowingMediaAccessAlert = true
            isAwaitingMediaAccessDecision = true
            telemetryService.recordTelemetry(
                .mediaAccessPromptShown,
                attributes: [
                    "permission.excluded_category_present": .bool(
                        permissionSummary.excludedCategoryDescription != nil
                    )
                ]
            )
            model.persistSnapshot()
            return
        }

        await continueBackupPreflight()
    }

    func goBack() async {
        resetPromptState()
        await model.handleResultForPage(.permissions, result: .cancel, target: nil)
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
        guard isAwaitingLowBatteryDecision else {
            return
        }
        isAwaitingLowBatteryDecision = false
        isShowingLowBatteryWarning = false
        telemetryService.recordInteraction(name: "continue_anyway_tapped", location: "low_battery_warning")
        telemetryService.recordTelemetry(.lowBatteryContinued, attributes: [:])
        presentRemoveAfterBackupPrompt()
    }

    func cancelFromLowBattery() async {
        guard isAwaitingLowBatteryDecision else {
            return
        }
        isAwaitingLowBatteryDecision = false
        isShowingLowBatteryWarning = false
        telemetryService.recordInteraction(name: "not_now_tapped", location: "low_battery_warning")
        telemetryService.recordTelemetry(.lowBatteryCanceled, attributes: [:])
        resetPromptState()
        await model.handleResultForPage(.permissions, result: .cancel, target: .lowBatteryDeclined)
    }

    func updateMediaAccessTapped() {
        telemetryService.recordInteraction(name: "update_media_access_tapped", location: "media_access_alert")
    }

    func continueAfterMediaAccessUpdate() async {
        await continueBackupFromMediaAccess()
    }

    func continueBackupFromMediaAccessNotNow() async {
        telemetryService.recordInteraction(name: "not_now_tapped", location: "media_access_alert")
        await continueBackupFromMediaAccess()
    }

    func selectRemoveAfterBackupPreference(_ shouldRemove: Bool) async {
        guard isAwaitingRemoveAfterBackupDecision else {
            return
        }
        isAwaitingRemoveAfterBackupDecision = false
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
        guard isAwaitingMediaAccessDecision else {
            return
        }
        isAwaitingMediaAccessDecision = false
        isShowingMediaAccessAlert = false
        telemetryService.recordTelemetry(.mediaAccessContinued, attributes: [:])
        await continueBackupPreflight()
    }

    private func continueBackupPreflight() async {
        if model.permissionSummary.lowBatteryWarningNeeded && !model.permissionSummary.isCharging {
            isShowingLowBatteryWarning = true
            isAwaitingLowBatteryDecision = true
            telemetryService.recordTelemetry(.lowBatteryPromptShown, attributes: [:])
            model.persistSnapshot()
            return
        }

        presentRemoveAfterBackupPrompt()
    }

    private func presentRemoveAfterBackupPrompt() {
        isShowingRemoveAfterBackupPrompt = true
        isAwaitingRemoveAfterBackupDecision = true
        telemetryService.recordTelemetry(.removeAfterBackupPromptShown, attributes: [:])
        model.persistSnapshot()
    }

    private func resetPromptState() {
        isAwaitingMediaAccessDecision = false
        isAwaitingLowBatteryDecision = false
        isAwaitingRemoveAfterBackupDecision = false
        isShowingMediaAccessAlert = false
        isShowingLowBatteryWarning = false
        isShowingRemoveAfterBackupPrompt = false
    }

}
