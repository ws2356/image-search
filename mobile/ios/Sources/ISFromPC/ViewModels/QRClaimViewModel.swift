import SwiftUI

@MainActor
public class QRClaimViewModel: ObservableObject {
    let qrClaimPayload: QRClaimPayload
    var onCompletion: ((Result<QRClaimResult, Error>) -> Void)?

    init(qrClaimPayload: QRClaimPayload) {
        self.qrClaimPayload = qrClaimPayload
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
            onCompletion?(.success(result))
        } catch {
            onCompletion?(.failure(error))
        }
    }
}
