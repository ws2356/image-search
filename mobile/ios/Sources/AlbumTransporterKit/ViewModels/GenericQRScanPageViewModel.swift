import Foundation
import Common

@MainActor
struct GenericQRScanPageViewModel: ScanningBaseViewModel {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    func onQRScanned(scannedValue: String) async {
        telemetryService.recordInteraction(name: "qr_scanned", location: "generic_scan")
        let result = GenericQRScanPageResult(result: .success(scannedValue))
        await model.onGenericQRScanCompleted(with: result)
    }

    func onBackTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "generic_scan")
        let result = GenericQRScanPageResult(result: .failure(.cancel))
        await model.onGenericQRScanCompleted(with: result)
    }

    func onOpenSettingsTapped() async {
        telemetryService.recordInteraction(name: "open_settings_tapped", location: "generic_scan")
        let result = GenericQRScanPageResult(result: .failure(.cancel))
        await model.onGenericQRScanCompleted(with: result)
    }

    func onScannerFailed(error: Error) async {
        telemetryService.recordInteraction(name: "scanner_failed", location: "generic_scan")
        let result = GenericQRScanPageResult(result: .failure(.scannerFailed))
        await model.onGenericQRScanCompleted(with: result)
    }
}
