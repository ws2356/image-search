import Foundation

@MainActor
struct ScanningPageViewModel {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    func onQRScanned(scannedValue: String) async {
        telemetryService.recordInteraction(name: "start_pairing_tapped", location: "pairing")
        let result = ScanningPageResult(result: .success(scannedValue))
        await model.onScanningCompleted(with: result)
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        let result = ScanningPageResult(result: .failure(.unknown))
        await model.onScanningCompleted(with: result)
    }

    func openSettingsTapped() async {
        telemetryService.recordInteraction(name: "open_settings_tapped", location: "pairing_scanner")
        let result = ScanningPageResult(result: .failure(.unknown))
        await model.onScanningCompleted(with: result)
    }

    func scannerFailed() async {
        telemetryService.recordInteraction(name: "scanner_failed", location: "pairing_scanner")
        let result = ScanningPageResult(result: .failure(.scannerFailed))
        await model.onScanningCompleted(with: result)
    }
}
