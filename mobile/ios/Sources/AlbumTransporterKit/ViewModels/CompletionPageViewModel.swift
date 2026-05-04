@MainActor
struct CompletionPageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var summary: CompletionSummary {
        model.completionSummary
    }

    func returnHome() async {
        await model.returnHome()
    }

    func returnHomeTapped() async {
        model.recordInteraction(name: "return_home_tapped", location: "completion")
        await model.returnHome()
    }
}
