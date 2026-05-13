import Foundation

@MainActor
struct ScanningPageViewModel {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    var status: PairingStatus {
        model.pairingStatus
    }

    func onQRScanned(scannedValue: String) async {
        model.scannedQRCodeValue = scannedValue
        telemetryService.recordInteraction(name: "start_pairing_tapped", location: "pairing")
        await model.handleResultForPage(.scan, result: .success, target: .primary)
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        await model.handleResultForPage(.scan, result: .cancel, target: nil)
    }

    func openSettingsTapped() {
        telemetryService.recordInteraction(name: "open_settings_tapped", location: "pairing_scanner")
        Task { [model] in
            await model.handleResultForPage(.scan, result: .cancel, target: nil)
        }
    }

    func scannerFailed() {
        telemetryService.recordInteraction(name: "scanner_failed", location: "pairing_scanner")
        Task { [model] in
            await model.handleResultForPage(.scan, result: .failure, target: nil)
        }
    }
}
