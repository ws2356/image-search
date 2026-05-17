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

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                // Invalid QR code - create failed status with error message
                let failedStatus = PairingStatus(
                    phase: .failed,
                    backupFlowState: .pendingPairing,
                    desktopName: nil,
                    sessionID: nil,
                    transport: nil,
                    message: error.message
                )
                let result = PairingPageResult(result: .failure(.invalidQR(detail: error)), pairingStatus: failedStatus)
                await model.onPairingCompleted(with: result)
            }
            return
        }

        // Start pairing with the decoded payload
        let pairingResult = await model.pairingService.startPairing(using: payload)
        
        // Check if route is still .pair (user might have cancelled)
        if case .pair = model.route {
            // Report the result with the pairing status
            let pageResult: PairingPageResult
            if pairingResult.phase == .paired {
                pageResult = PairingPageResult(result: .success(()), pairingStatus: pairingResult)
            } else if pairingResult.phase == .pairing {
                // Unexpected phase - service is still in pairing state
                pageResult = PairingPageResult(result: .failure(.unexpectedPhase), pairingStatus: pairingResult)
            } else {
                // Failed or other phase
                pageResult = PairingPageResult(result: .failure(.pairingFailed), pairingStatus: pairingResult)
            }
            await model.onPairingCompleted(with: pageResult)
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
