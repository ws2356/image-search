import SwiftUI

@MainActor
final class PairingPageViewModel: ObservableObject {
    private let model: any PairingPageModeling
    private let telemetryService: TelemetryService
    private var hasStartedPairingAttempt = false

    init(model: any PairingPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    var status: PairingStatus {
        model.pairingStatus
    }

    func orchestratePairing() async {
        guard model.route == .pair, model.pairingStatus.phase == .pairing else {
            return
        }
        guard !hasStartedPairingAttempt else {
            return
        }
        hasStartedPairingAttempt = true
        defer { hasStartedPairingAttempt = false }

        let payloadResult = model.qrCodePayloadDecoderForPairingPage.decode(
            scannedValue: model.scannedQRCodeValue
        )

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                model.handleInvalidPairingPayload(message: error.message)
            }
            return
        }

        let result = await model.pairingServiceForPairingPage.startPairing(using: payload)
        guard model.route == .pair else {
            model.persistSnapshot()
            return
        }
        await model.handlePairingAttemptCompleted(result)
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
