import SwiftUI
import Common

public struct ISQRRootView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ISQRRootViewModel

    public init(qrPayload: QRClaimPayload) {
        _viewModel = StateObject(wrappedValue: ISQRRootViewModel(qrClaimPayload: qrPayload))
    }

    public var body: some View {
        navigationContainer
    }

    @ViewBuilder
    private var navigationContainer: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                contentView
            }
        } else {
            NavigationView {
                contentView
            }
            .navigationViewStyle(.stack)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .claiming:
            QRClaimView(viewModel: viewModel.claimViewModel)
        case .result(let result):
            QRTransferResultView(result: result, onDismiss: { dismiss() })
        case .error(let title, let message):
            let errorVM = ISQRErrorViewModel(
                title: title,
                message: message,
                onRetry: { await viewModel.retry() },
                onDismiss: { dismiss() }
            )
            ErrorStateView(viewModel: errorVM)
        }
    }
}
