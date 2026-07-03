import SwiftUI
import Common

#if os(iOS)
@MainActor
public class ISQRRootViewModel: ObservableObject, ViewLifeCycle, QRClaimDelegate, QRScanDelegate, ISQRDeliverDelegate, ISQRErrorDelegate {
    public enum State {
        case scan
        case claiming
        case result(QRClaimResult)
        case error(title: String, message: String)
    }

    @Published public private(set) var state: State
    let navigator: Navigator
    private(set) var qrClaimPayload: QRClaimPayload?

    var qrClaimResult: QRClaimResult? {
        didSet {
            let oldUrls = oldValue?.fileUrls ?? []
            let newUrls = qrClaimResult?.fileUrls ?? []
            for oldUrl in oldUrls where !newUrls.contains(oldUrl) {
                Task {
                    await self.cleanupStashedFile(oldUrl)
                }
            }
        }
    }

    public init(
        initialState: State = .claiming,
        qrClaimPayload: QRClaimPayload? = nil,
        navigator: Navigator
    ) {
        self.state = initialState
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
            self.qrClaimResult = claimResult
            state = .result(claimResult)
        case .failure(let error):
            let title = "Transfer Failed"
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .error(title: title, message: message)
        }
    }
    
    public func onDeliverComplete() {
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
    
    func onAppear() {
    }
    
    func onDisappear() {
        for fileUrl in qrClaimResult?.fileUrls ?? [] {
            Task {
                await self.cleanupStashedFile(fileUrl)
            }
        }
    }
    
    private func handleScannedQRCode(_ scannedValue: String) async {
        guard let url = URL(string: scannedValue),
              let payload = QRClaimPayload(universalLinkURL: url) else {
            state = .error(title: "Invalid QR Code", message: "Could not parse the scanned QR code.")
            return
        }
        self.qrClaimPayload = payload
        state = .claiming
    }
    
    private func cleanupStashedFile(_ fileUrl: URL) async {
        do {
            try await FileManager.default.removeItem(at: fileUrl)
        } catch (let error) {
            LocalLog.error("cleanup stashed file failed: \(error)")
        }
    }
}
#endif
