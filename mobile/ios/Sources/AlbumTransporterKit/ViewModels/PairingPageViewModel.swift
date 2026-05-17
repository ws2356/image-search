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
        guard case .pair(let qrString) = model.route,
              model.backupFlowState == .pendingPairing
        else {
            return
        }
        guard !hasStartedPairingAttempt else {
            return
        }
        hasStartedPairingAttempt = true
        defer { hasStartedPairingAttempt = false }

        let payloadResult = qrCodePayloadDecoder.decode(scannedValue: qrString)

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                let result = PairingPageResult(
                    result: .failure(
                        .decoding(message: error.message)
                    )
                )
                await model.onPairingCompleted(with: result)
            }
            return
        }

        let pairingResult: Result<PairingResponse, PairingError> = await model.pairingService.startPairing(using: payload)

        if case .pair = model.route {
            let pageResult = PairingPageResult(result: pairingResult)
            await model.onPairingCompleted(with: pageResult)
        }
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        let result = PairingPageResult(result: .failure(.cancel))
        await model.onPairingCompleted(with: result)
    }
}
