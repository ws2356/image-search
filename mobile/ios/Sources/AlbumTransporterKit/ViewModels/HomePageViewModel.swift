@MainActor
struct HomePageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var summary: HomeSummary {
        model.homeSummary
    }

    func handlePrimaryAction() async {
        await model.handleHomePrimaryAction()
    }

    func openScanFlow() async {
        await model.openScanFlow()
    }
}
