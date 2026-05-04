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

    func handlePrimaryActionTapped() async {
        model.recordInteraction(name: "primary_action_tapped", location: "home")
        await model.handleHomePrimaryAction()
    }

    func openScanFlow() async {
        await model.openScanFlow()
    }

    func openScanFlowTapped() async {
        model.recordInteraction(name: "reconnect_tapped", location: "home")
        await model.openScanFlow()
    }
}
