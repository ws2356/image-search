import SwiftUI
import Common

@MainActor
protocol QRClaimDelegate {
    func onClaimCompletion(_ result: Result<QRClaimResult, Error>) -> Void
}

@MainActor
class QRClaimViewModel: ObservableObject {
    let qrClaimPayload: QRClaimPayload
    let delegate: QRClaimDelegate
    let appIdentityProvider: AppIdentityProviding
    var onCompletion: ((Result<QRClaimResult, Error>) -> Void)?

    init(
        qrClaimPayload: QRClaimPayload,
        delegate: QRClaimDelegate,
        appIdentityProvider: AppIdentityProviding = KeychainAppIdentityProvider(
            localDeviceIdentifierProvider: LocalDeviceIdentifierStore()
        )
    ) {
        self.qrClaimPayload = qrClaimPayload
        self.delegate = delegate
        self.appIdentityProvider = appIdentityProvider
    }

    func claim() async {
        let client = QRTriggerDownloadClient(appIdentityProvider: appIdentityProvider)
        do {
            let result = try await client.claim(
                hosts: qrClaimPayload.ips,
                port: qrClaimPayload.port,
                tlsPort: qrClaimPayload.tlsPort,
                sessionId: qrClaimPayload.sessionId,
                optCode: qrClaimPayload.optCode,
                pcDeviceId: qrClaimPayload.deviceId
            )
            self.delegate.onClaimCompletion(.success(result))
        } catch {
            self.delegate.onClaimCompletion(.failure(error))
        }
    }
}
