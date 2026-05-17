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
              model.pairingStatus.backupFlowState == .pendingPairing
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
                let failedStatus = PairingStatus(
                    backupFlowState: .pendingPairing,
                    desktopName: nil,
                    sessionID: nil,
                    transport: nil
                )
                let result = PairingPageResult(result: .failure(.invalidQR(detail: error)), pairingStatus: failedStatus)
                await model.onPairingCompleted(with: result)
            }
            return
        }

        let pairingResult = await model.pairingService.startPairing(using: payload)

        if case .pair = model.route {
            let pageResult: PairingPageResult = pairingResult.backupFlowState == .pairingCompleted
                ? PairingPageResult(result: .success(()), pairingStatus: pairingResult)
                : PairingPageResult(result: .failure(.pairingFailed), pairingStatus: pairingResult)
            await model.onPairingCompleted(with: pageResult)
        }
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        let result = PairingPageResult(result: .failure(.cancelled))
        await model.onPairingCompleted(with: result)
    }
}
