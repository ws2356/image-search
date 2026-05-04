import SwiftUI

@MainActor
struct PermissionsPageViewModel {
    private let model: any PermissionsPageModeling

    init(model: any PermissionsPageModeling) {
        self.model = model
    }

    var summary: PermissionSummary {
        model.permissionSummary
    }

    var removeAfterBackupEnabled: Bool {
        model.removeAfterBackupEnabled
    }

    var isShowingLowBatteryWarning: Bool {
        model.isShowingLowBatteryWarning
    }

    var isShowingMediaAccessAlert: Bool {
        model.isShowingMediaAccessAlert
    }

    var isShowingRemoveAfterBackupPrompt: Bool {
        model.isShowingRemoveAfterBackupPrompt
    }

    var mediaAccessAlertMessage: String {
        model.mediaAccessAlertMessage
    }

    var isShowingLowBatteryWarningBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingLowBatteryWarning },
            set: { model.isShowingLowBatteryWarning = $0 }
        )
    }

    var isShowingMediaAccessAlertBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingMediaAccessAlert },
            set: { model.isShowingMediaAccessAlert = $0 }
        )
    }

    var isShowingRemoveAfterBackupPromptBinding: Binding<Bool> {
        Binding(
            get: { model.isShowingRemoveAfterBackupPrompt },
            set: { model.isShowingRemoveAfterBackupPrompt = $0 }
        )
    }

    func startPreflight() async {
        model.recordInteraction(name: "start_backup_tapped", location: "permissions")
        await model.startBackup()
    }

    func startBackup() async {
        await model.startBackup()
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        model.setRemoveAfterBackupEnabled(isEnabled)
    }

    func goBack() async {
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
        model.recordInteraction(name: "continue_anyway_tapped", location: "low_battery_warning")
        await model.continuePastLowBatteryWarning()
    }

    func cancelFromLowBattery() async {
        model.recordInteraction(name: "not_now_tapped", location: "low_battery_warning")
        await model.cancelBackupFromLowBatteryWarning()
    }

    func updateMediaAccessTapped() {
        model.recordInteraction(name: "update_media_access_tapped", location: "media_access_alert")
    }

    func continueAfterMediaAccessUpdate() async {
        await model.continueBackupFromMediaAccess()
    }

    func continueBackupFromMediaAccessNotNow() async {
        model.recordInteraction(name: "not_now_tapped", location: "media_access_alert")
        await model.continueBackupFromMediaAccess()
    }

    func selectRemoveAfterBackupPreference(_ shouldRemove: Bool) async {
        model.recordInteraction(
            name: shouldRemove ? "remove_after_backup_selected" : "keep_originals_selected",
            location: "remove_after_backup_prompt"
        )
        await model.selectRemoveAfterBackupPreferenceAndContinue(shouldRemove)
    }
}
