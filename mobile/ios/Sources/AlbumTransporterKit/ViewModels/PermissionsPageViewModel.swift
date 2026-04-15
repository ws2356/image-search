@MainActor
struct PermissionsPageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var summary: PermissionSummary {
        model.permissionSummary
    }

    var removeAfterBackupEnabled: Bool {
        model.removeAfterBackupEnabled
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
}
