@MainActor
struct ErrorPageViewModel {
    private let model: any AppPageModeling

    init(model: any AppPageModeling) {
        self.model = model
    }

    var summary: ErrorSummary {
        model.errorSummary
    }

    func retryTapped() {
        model.recordInteraction(name: "retry_tapped", location: "error")
        Task { [model] in
            await model.handleResultForPage(.error, result: .success, target: nil)
        }
    }

    func cancelTapped() {
        model.recordInteraction(name: "cancel_tapped", location: "error")
        Task { [model] in
            await model.handleResultForPage(.error, result: .cancel, target: nil)
        }
    }
}
