import SwiftUI

@MainActor
public class ISQRRootViewModel: ObservableObject, QRClaimDelegate, QRScanDelegate, ISQRDeliverDelegate, ISQRErrorDelegate {
    public enum State {
        case scan
        case claiming
        case result(QRClaimResult)
        case error(title: String, message: String)
    }

    @Published public private(set) var state: State = .claiming
    let navigator: Navigator
    let qrClaimPayload: QRClaimPayload

    public init(qrClaimPayload: QRClaimPayload, navigator: Navigator) {
        self.qrClaimPayload = qrClaimPayload
        self.navigator = navigator
    }
    
    func onQRScanResult(_ result: QRScanResult) async {
        switch result {
        case .success(let qrLink):
            await self.handleScannedQRCode(qrLink)
        case .failure(let error):
            self.state = .error(title: "Invalid QR Code", message: "Could not parse the scanned QR code \(error.localizedDescription).")
        case .canceled:
            self.navigator.requestExit()
        case .changeSetting:
            self.navigator.requestExit()
        }
    }
    
    func onClaimCompletion(_ result: Result<QRClaimResult, any Error>) {
        switch result {
        case .success(let claimResult):
            state = .result(claimResult)
        case .failure(let error):
            let title = "Transfer Failed"
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .error(title: title, message: message)
        }
    }
    
    func onDeliverComplete() {
        navigator.requestExit()
    }
    
    func onErrorHandlingResult(_ result: ErrorHandlingResult) {
        switch result {
        case .retry:
            state = .scan
        case .cancel:
            self.navigator.requestExit()
        }
    }
    
    private func handleScannedQRCode(_ scannedValue: String) async {
        guard let url = URL(string: scannedValue),
              let payload = QRClaimPayload(universalLinkURL: url) else {
            state = .error(title: "Invalid QR Code", message: "Could not parse the scanned QR code.")
            return
        }
        state = .claiming
    }
}
