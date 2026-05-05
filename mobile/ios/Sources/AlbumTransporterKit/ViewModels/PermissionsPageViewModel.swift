import SwiftUI

@MainActor
final class PermissionsPageViewModel: ObservableObject, ViewModelProtocol {
    private let model: any PermissionsPageModeling
    private let onPageResultHandler: ((_ result: PageResult, _ target: PageTarget?) -> Void)?

    @Published var isShowingLowBatteryWarning = false
    @Published var isShowingMediaAccessAlert = false
    @Published var isShowingRemoveAfterBackupPrompt = false
    @Published var mediaAccessAlertMessage = "Do you want to expand access permission to back up more or all media files in your photo library?"

    private var isAwaitingMediaAccessDecision = false
    private var isAwaitingLowBatteryDecision = false
    private var isAwaitingRemoveAfterBackupDecision = false
    private var isRunningPermissionsPreflight = false

    init(
        model: any PermissionsPageModeling,
        onPageResult: ((_ result: PageResult, _ target: PageTarget?) -> Void)? = nil
    ) {
        self.model = model
        self.onPageResultHandler = onPageResult
    }

    var summary: PermissionSummary {
        model.permissionSummary
    }

    var removeAfterBackupEnabled: Bool {
        model.removeAfterBackupEnabled
    }

    func startPreflight() async {
        guard !isRunningPermissionsPreflight else {
            return
        }
        isRunningPermissionsPreflight = true
        resetPromptState()

        let permissionSummary = await model.permissionService.loadPermissionSummary()
        model.permissionSummary = permissionSummary
        model.beginTelemetrySpan(.backupPreflight, attributes: [:])
        model.recordTelemetry(.backupPreflightStarted, attributes: [:])
        model.recordInteraction(name: "start_backup_tapped", location: "permissions")

        guard permissionSummary.mediaScope == .full else {
            isShowingMediaAccessAlert = true
            isAwaitingMediaAccessDecision = true
            model.recordTelemetry(
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

    func startBackup() async {
        await startPreflight()
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        model.setRemoveAfterBackupEnabled(isEnabled)
    }

    func goBack() async {
        resetPromptState()
        if onPageResultHandler != nil {
            onPageResult(.cancel, target: nil)
            return
        }
        await model.returnHome()
    }

    func recordLowBatteryDialogPresented() {
        model.recordDialogView(name: "low_battery_warning")
    }

    func recordMediaAccessDialogPresented() {
        model.recordDialogView(name: "media_access_alert")
    }

    func recordRemoveAfterBackupDialogPresented() {
        model.recordDialogView(name: "remove_after_backup_prompt")
    }

    func continuePastLowBattery() async {
        guard isAwaitingLowBatteryDecision else {
            return
        }
        isAwaitingLowBatteryDecision = false
        isShowingLowBatteryWarning = false
        model.recordInteraction(name: "continue_anyway_tapped", location: "low_battery_warning")
        model.recordTelemetry(.lowBatteryContinued, attributes: [:])
        presentRemoveAfterBackupPrompt()
    }

    func cancelFromLowBattery() async {
        guard isAwaitingLowBatteryDecision else {
            return
        }
        isAwaitingLowBatteryDecision = false
        isShowingLowBatteryWarning = false
        model.recordInteraction(name: "not_now_tapped", location: "low_battery_warning")
        model.recordTelemetry(.lowBatteryCanceled, attributes: [:])
        resetPromptState()
        if onPageResultHandler != nil {
            onPageResult(.cancel, target: .lowBatteryDeclined)
            return
        }
        await model.abortPreflightAndReturnHome(reason: "low_battery_declined")
    }

    func updateMediaAccessTapped() {
        model.recordInteraction(name: "update_media_access_tapped", location: "media_access_alert")
    }

    func continueAfterMediaAccessUpdate() async {
        await continueBackupFromMediaAccess()
    }

    func continueBackupFromMediaAccessNotNow() async {
        model.recordInteraction(name: "not_now_tapped", location: "media_access_alert")
        await continueBackupFromMediaAccess()
    }

    func selectRemoveAfterBackupPreference(_ shouldRemove: Bool) async {
        guard isAwaitingRemoveAfterBackupDecision else {
            return
        }
        isAwaitingRemoveAfterBackupDecision = false
        isShowingRemoveAfterBackupPrompt = false
        model.recordInteraction(
            name: shouldRemove ? "remove_after_backup_selected" : "keep_originals_selected",
            location: "remove_after_backup_prompt"
        )
        model.recordTelemetry(
            .removeAfterBackupPreferenceSelected,
            attributes: [
                "backup.remove_after_backup_enabled": .bool(shouldRemove)
            ]
        )
        isRunningPermissionsPreflight = false
        // TODO: agent, no need call onPageResult here because this is not a terminating event for this page
        if onPageResultHandler != nil {
            onPageResult(
                .success,
                target: shouldRemove ? .removeTransferredMedia : .keepOriginals
            )
            return
        }
        model.setRemoveAfterBackupEnabled(shouldRemove)
        await model.startTransfer()
    }

    private func continueBackupFromMediaAccess() async {
        guard isAwaitingMediaAccessDecision else {
            return
        }
        isAwaitingMediaAccessDecision = false
        isShowingMediaAccessAlert = false
        model.recordTelemetry(.mediaAccessContinued, attributes: [:])
        await continueBackupPreflight()
    }

    private func continueBackupPreflight() async {
        if model.permissionSummary.lowBatteryWarningNeeded && !model.permissionSummary.isCharging {
            isShowingLowBatteryWarning = true
            isAwaitingLowBatteryDecision = true
            model.recordTelemetry(.lowBatteryPromptShown, attributes: [:])
            model.persistSnapshot()
            return
        }

        presentRemoveAfterBackupPrompt()
    }

    private func presentRemoveAfterBackupPrompt() {
        isShowingRemoveAfterBackupPrompt = true
        isAwaitingRemoveAfterBackupDecision = true
        model.recordTelemetry(.removeAfterBackupPromptShown, attributes: [:])
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

    func onPageResult(_ result: PageResult, target: PageTarget?) {
        onPageResultHandler?(result, target)
    }
}
