import SwiftUI

struct QRClaimView: View {
    @ObservedObject var viewModel: QRClaimViewModel

    var body: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.claim()
        }
    }
}
