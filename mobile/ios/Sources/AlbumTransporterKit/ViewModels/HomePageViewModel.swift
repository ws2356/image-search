@MainActor
struct HomePageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var summary: HomeSummary {
        model.homeSummary
    }

    func handlePrimaryActionTapped() async {
        model.recordInteraction(name: "primary_action_tapped", location: "home")
        await model.handleResultForPage(.home, result: .success, target: .primary)
    }

    func openScanFlowTapped() async {
        model.recordInteraction(name: "reconnect_tapped", location: "home")
        await model.handleResultForPage(.home, result: .success, target: .secondary)
    }
}
