import SwiftUI

struct QRClaimView: View {
    let qrClaimPayload: QRClaimPayload
    let delegate: QRClaimDelegate
    @StateObject var viewModel: QRClaimViewModel
    
    init(qrClaimPayload: QRClaimPayload, delegate: QRClaimDelegate) {
        self.qrClaimPayload = qrClaimPayload
        self.delegate = delegate
        self._viewModel = StateObject(wrappedValue: QRClaimViewModel(qrClaimPayload: qrClaimPayload, delegate: delegate))
    }
    
    var body: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.claim()
        }
    }
}
