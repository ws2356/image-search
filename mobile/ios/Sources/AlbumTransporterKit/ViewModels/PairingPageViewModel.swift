@MainActor
struct PairingPageViewModel {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    var status: PairingStatus {
        model.pairingStatus
    }

    func scanAgainTapped() async {
        telemetryService.recordInteraction(name: "scan_again_tapped", location: "pairing")
        await model.handleResultForPage(.pair, result: .success, target: .secondary)
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        await model.handleResultForPage(.pair, result: .cancel, target: nil)
    }
}
