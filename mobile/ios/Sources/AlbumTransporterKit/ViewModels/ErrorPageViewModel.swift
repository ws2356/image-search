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

    func retryTapped() {
        telemetryService.recordInteraction(name: "retry_tapped", location: "error")
        Task { [model] in
            await model.handleResultForPage(.error, result: .success, target: nil)
        }
    }

    func cancelTapped() {
        telemetryService.recordInteraction(name: "cancel_tapped", location: "error")
        Task { [model] in
            await model.handleResultForPage(.error, result: .cancel, target: nil)
        }
    }
}
