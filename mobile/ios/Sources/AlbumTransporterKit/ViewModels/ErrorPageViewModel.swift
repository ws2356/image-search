@MainActor
struct ErrorPageViewModel: ViewModelProtocol {
    private let model: any AppPageModeling
    private let onPageResultHandler: ((_ result: PageResult, _ target: PageTarget?) -> Void)?

    init(
        model: any AppPageModeling,
        onPageResult: ((_ result: PageResult, _ target: PageTarget?) -> Void)? = nil
    ) {
        self.model = model
        self.onPageResultHandler = onPageResult
    }

    var summary: ErrorSummary {
        model.errorSummary
    }

    func retryTapped() {
        model.recordInteraction(name: "retry_tapped", location: "error")
        onPageResult(.success, target: nil)
    }

    func cancelTapped() {
        model.recordInteraction(name: "cancel_tapped", location: "error")
        onPageResult(.cancel, target: nil)
    }

    func onPageResult(_ result: PageResult, target: PageTarget?) {
        onPageResultHandler?(result, target)
    }
}
