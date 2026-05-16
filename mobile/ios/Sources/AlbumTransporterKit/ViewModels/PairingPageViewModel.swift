import SwiftUI

@MainActor
final class PairingPageViewModel: ObservableObject {
    private let model: any PairingPageModeling
    private let telemetryService: TelemetryService
    private let qrCodePayloadDecoder: QRCodePayloadDecoding
    private var hasStartedPairingAttempt = false

    init(
        model: any PairingPageModeling,
        telemetryService: TelemetryService,
        qrCodePayloadDecoder: QRCodePayloadDecoding
    ) {
        self.model = model
        self.telemetryService = telemetryService
        self.qrCodePayloadDecoder = qrCodePayloadDecoder
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

        let payloadResult = qrCodePayloadDecoder.decode(
            scannedValue: model.scannedQRCodeValue
        )

        // TODO: pass a pairing error struct to be consumed by error page
        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                model.handleInvalidPairingPayload(message: error.message)
            }
            return
        }

        // TODO: do not propogate message, just consume it within the pairing page
        let result = await model.pairingService.startPairing(using: payload)
        guard model.route == .pair else {
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
