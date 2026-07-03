#if os(iOS)
import SwiftUI
import Common
import Factory

@MainActor
protocol QRClaimDelegate {
    func onClaimCompletion(_ result: Result<QRClaimResult, Error>) -> Void
}

@MainActor
class QRClaimViewModel: ObservableObject {
    let qrClaimPayload: QRClaimPayload
    let delegate: QRClaimDelegate
    @Injected(\.appIdentityProvider) private(set) var appIdentityProvider: AppIdentityProviding
    var onCompletion: ((Result<QRClaimResult, Error>) -> Void)?

    init(
        qrClaimPayload: QRClaimPayload,
        delegate: QRClaimDelegate,
    ) {
        self.qrClaimPayload = qrClaimPayload
        self.delegate = delegate
    }

    func claim() async {
        let client = QRTriggerDownloadClient(appIdentityProvider: appIdentityProvider)
        do {
            let result = try await client.claim(
                hosts: qrClaimPayload.ips,
                port: qrClaimPayload.port,
                tlsPort: qrClaimPayload.tlsPort,
                sessionId: qrClaimPayload.sessionId,
                optCode: qrClaimPayload.optCode
            )
            self.delegate.onClaimCompletion(.success(result))
        } catch {
            self.delegate.onClaimCompletion(.failure(error))
        }
    }
}
#endif
