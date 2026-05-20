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

    func orchestratePairing() async {
        guard case .pair(let qrString) = model.route else {
            await model.onPairingCompleted(with: PairingPageResult(result: .failure(.cancel)))
            return
        }

        if model.backupFlowState != .pendingPairing {
            recordDiagnosticCheckpoint(
                area: "pairing_orchestration_skipped",
                attributes: [
                    "pairing.skip_reason": .string("route_or_flow_state_mismatch state=\(model.backupFlowState.rawValue)")
                ]
            )
        }
            // Navigate home so the page doesn't stay stuck with nothing happening.
        guard !hasStartedPairingAttempt else {
            recordDiagnosticCheckpoint(
                area: "pairing_orchestration_skipped",
                attributes: [
                    "pairing.skip_reason": .string("pairing_attempt_already_running")
                ]
            )
            return
        }
        hasStartedPairingAttempt = true
        defer { hasStartedPairingAttempt = false }
        recordDiagnosticCheckpoint(
            area: "pairing_orchestration_started",
            attributes: [
                "pairing.qr_length": .int(qrString.count)
            ]
        )

        let payloadResult = qrCodePayloadDecoder.decode(scannedValue: qrString)

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                recordDiagnosticCheckpoint(
                    area: "pairing_payload_decoded",
                    attributes: [
                        "pairing.decode_result": .string("failure"),
                        "pairing.failure_reason": .string(error.title)
                    ]
                )
                let result = PairingPageResult(
                    result: .failure(
                        .decoding(message: error.message)
                    )
                )
                await model.onPairingCompleted(with: result)
            }
            return
        }
        recordDiagnosticCheckpoint(
            area: "pairing_payload_decoded",
            attributes: [
                "pairing.decode_result": .string("success"),
                "pairing.session_id_length": .int(payload.sessionID.count),
                "pairing.endpoint_target_count": .int(payload.endpointTargets.count),
                "pairing.usb_port_present": .bool(payload.suggestedUSBPort != nil)
            ]
        )

        let pairingResult: Result<PairingResponse, PairingError> = await model.pairingService.startPairing(using: payload)
        switch pairingResult {
        case .success(let response):
            recordDiagnosticCheckpoint(
                area: "pairing_service_result",
                attributes: [
                    "pairing.result": .string("success"),
                    "pairing.transport": .string(response.transport.rawValue),
                    "pairing.desktop_name_present": .bool(!response.desktopName.isEmpty)
                ]
            )
        case .failure(let error):
            recordDiagnosticCheckpoint(
                area: "pairing_service_result",
                attributes: [
                    "pairing.result": .string("failure"),
                    "pairing.failure_reason": .string(error.title),
                    "pairing.failure_message": .string(error.message)
                ]
            )
        }

        if case .pair = model.route {
            let pageResult = PairingPageResult(result: pairingResult)
            await model.onPairingCompleted(with: pageResult)
        } else {
            recordDiagnosticCheckpoint(
                area: "pairing_result_dropped",
                attributes: [
                    "pairing.drop_reason": .string("route_changed_before_apply")
                ]
            )
        }
    }

    func backTapped() async {
        telemetryService.recordInteraction(name: "back_tapped", location: "pairing")
        let result = PairingPageResult(result: .failure(.cancel))
        await model.onPairingCompleted(with: result)
    }

    private func recordDiagnosticCheckpoint(
        area: String,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        var diagnosticAttributes = attributes
        diagnosticAttributes["diagnostic.area"] = .string(area)
        diagnosticAttributes["app.route"] = .string(routeName(model.route))
        diagnosticAttributes["backup.flow_state"] = .string(model.backupFlowState.rawValue)
        diagnosticAttributes["pairing.attempt_in_flight"] = .bool(hasStartedPairingAttempt)
        telemetryService.recordTelemetry(.diagnosticCheckpoint, attributes: diagnosticAttributes)
    }

    private func routeName(_ route: AppRoute) -> String {
        switch route {
        case .home:
            return "home"
        case .scan:
            return "scan"
        case .pair:
            return "pair"
        case .permissions:
            return "permissions"
        case .transfer:
            return "transfer"
        case .completed:
            return "completed"
        case .error:
            return "error"
        }
    }
}
