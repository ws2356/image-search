import SwiftUI

@MainActor
public class ISQRRootViewModel: ObservableObject {
    public enum State {
        case claiming
        case result(QRClaimResult)
        case error(title: String, message: String)
    }

    @Published public private(set) var state: State = .claiming
    @Published public private(set) var claimViewModel: QRClaimViewModel

    public init(qrClaimPayload: QRClaimPayload) {
        self.claimViewModel = QRClaimViewModel(qrClaimPayload: qrClaimPayload)
        self.claimViewModel.onCompletion = { [weak self] result in
            self?.handleClaimResult(result)
        }
    }

    public func retry() {
        state = .claiming
        let newVM = QRClaimViewModel(qrClaimPayload: claimViewModel.qrClaimPayload)
        newVM.onCompletion = { [weak self] result in
            self?.handleClaimResult(result)
        }
        claimViewModel = newVM
    }

    private func handleClaimResult(_ result: Result<QRClaimResult, Error>) {
        switch result {
        case .success(let claimResult):
            state = .result(claimResult)
        case .failure(let error):
            let title = "Transfer Failed"
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .error(title: title, message: message)
        }
    }
}
