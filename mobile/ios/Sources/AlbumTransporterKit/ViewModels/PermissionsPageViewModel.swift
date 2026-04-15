@MainActor
struct PermissionsPageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var summary: PermissionSummary {
        model.permissionSummary
    }

    func startBackup() async {
        await model.startBackup()
    }

    func goBack() async {
        await model.returnHome()
    }
}
