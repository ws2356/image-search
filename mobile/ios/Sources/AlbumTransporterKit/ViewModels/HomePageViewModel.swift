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
        await model.handleResultForPage(.home, result: .success, target: .primary)
    }

    func handlePrimaryActionTapped() async {
        model.recordInteraction(name: "primary_action_tapped", location: "home")
        await model.handleResultForPage(.home, result: .success, target: .primary)
    }

    func openScanFlow() async {
        await model.handleResultForPage(.home, result: .success, target: .secondary)
    }

    func openScanFlowTapped() async {
        model.recordInteraction(name: "reconnect_tapped", location: "home")
        await model.handleResultForPage(.home, result: .success, target: .secondary)
    }
}
