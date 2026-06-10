import SwiftUI

@MainActor
protocol QRClaimDelegate {
    func onClaimCompletion(_ result: Result<QRClaimResult, Error>) -> Void
}

@MainActor
class QRClaimViewModel: ObservableObject {
    let qrClaimPayload: QRClaimPayload
    let delegate: QRClaimDelegate
    var onCompletion: ((Result<QRClaimResult, Error>) -> Void)?

    init(qrClaimPayload: QRClaimPayload, delegate: QRClaimDelegate) {
        self.qrClaimPayload = qrClaimPayload
        self.delegate = delegate
    }

    func claim() async {
        let client = QRTriggerDownloadClient()
        do {
            let result = try await client.claim(
                hosts: qrClaimPayload.ips,
                port: qrClaimPayload.port,
                stashId: qrClaimPayload.stashId,
                optCode: qrClaimPayload.optCode
            )
            self.delegate.onClaimCompletion(.success(result))
        } catch {
            self.delegate.onClaimCompletion(.failure(error))
        }
    }
}
