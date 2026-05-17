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
        guard case .pair(let qrString) = model.route, model.pairingStatus.phase == .pairing else {
            return
        }
        guard !hasStartedPairingAttempt else {
            return
        }
        hasStartedPairingAttempt = true
        defer { hasStartedPairingAttempt = false }

        let payloadResult = qrCodePayloadDecoder.decode(scannedValue: qrString)

        // TODO: pass a pairing error struct to be consumed by error page
        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                model.handleInvalidPairingPayload(message: error.message)
            }
            return
        }

        // TODO: do not propogate message, just consume it within the pairing page
        let result = await model.pairingService.startPairing(using: payload)
        if case .pair = model.route {
            await model.handlePairingAttemptCompleted(result)
        }
    }

    // TODO: there should not be such a thing as "scan again" in pairing page. If failed, it should just navigate to error page
    func scanAgainTapped() async {
        telemetryService.recordInteraction(name: "scan_again_tapped", location: "pairing")
        let result = PairingPageResult(result: .success(()))
        await model.onPairingCompleted(with: result)
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        let result = PairingPageResult(result: .failure(.cancelled))
        await model.onPairingCompleted(with: result)
    }
}
