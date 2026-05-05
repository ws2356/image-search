@MainActor
struct HomePageViewModel: ViewModelProtocol {
    private let model: any AppPageModeling
    private let onPageResultHandler: ((_ result: PageResult, _ target: PageTarget?) -> Void)?

    init(
        model: any AppPageModeling,
        onPageResult: ((_ result: PageResult, _ target: PageTarget?) -> Void)? = nil
    ) {
        self.model = model
        self.onPageResultHandler = onPageResult
    }

    var summary: HomeSummary {
        model.homeSummary
    }

    func handlePrimaryAction() async {
        await model.handleHomePrimaryAction()
    }

    func handlePrimaryActionTapped() async {
        model.recordInteraction(name: "primary_action_tapped", location: "home")
        if onPageResultHandler != nil {
            onPageResult(.success, target: .primary)
            return
        }
        await model.handleHomePrimaryAction()
    }

    func openScanFlow() async {
        await model.openScanFlow()
    }

    func openScanFlowTapped() async {
        model.recordInteraction(name: "reconnect_tapped", location: "home")
        if onPageResultHandler != nil {
            onPageResult(.success, target: .secondary)
            return
        }
        await model.openScanFlow()
    }

    func onPageResult(_ result: PageResult, target: PageTarget?) {
        onPageResultHandler?(result, target)
    }
}
