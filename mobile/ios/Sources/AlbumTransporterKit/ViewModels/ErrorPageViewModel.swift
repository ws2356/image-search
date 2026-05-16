@MainActor
struct ErrorPageViewModel {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    var summary: ErrorSummary {
        model.errorSummary
    }

    func retryTapped() async {
        telemetryService.recordInteraction(name: "retry_tapped", location: "error")
        let result = ErrorPageResult(result: .success(()))
        await model.onErrorCompleted(with: result)
    }

    func cancelTapped() async {
        telemetryService.recordInteraction(name: "cancel_tapped", location: "error")
        let result = ErrorPageResult(result: .failure(.unknown))
        await model.onErrorCompleted(with: result)
    }
}
