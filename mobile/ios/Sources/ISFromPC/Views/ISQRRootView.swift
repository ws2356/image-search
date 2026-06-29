import SwiftUI
import Common

public struct ISQRRootView: View {
    @StateObject private var viewModel: ISQRRootViewModel
    let navigator: Navigator

    public init(qrPayload: QRClaimPayload, navigator: Navigator) {
        _viewModel = StateObject(wrappedValue: ISQRRootViewModel(qrClaimPayload: qrPayload, navigator: navigator))
        self.navigator = navigator
    }

    public var body: some View {
        navigationContainer
            .onDisappear {
                viewModel.onDisappear()
            }
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
        case .scan:
            ISQRScanPageView(delegate: viewModel)
        case .claiming:
            QRClaimView(qrClaimPayload: viewModel.qrClaimPayload, delegate: viewModel)
        case .result(let result):
            switch result {
            case .multiFile(let manifest, let host, let tlsPort, let sessionId, let correlationID):
                let vm = MultiFileReceiveViewModel(
                    manifest: manifest,
                    host: host,
                    tlsPort: tlsPort,
                    sessionId: sessionId,
                    correlationID: correlationID,
                    delegate: viewModel
                )
                MultiFileReceiveView(viewModel: vm)
            case .image, .file:
                let vm = MultiFileReceiveViewModel(
                    singleResult: result,
                    delegate: viewModel
                )
                MultiFileReceiveView(viewModel: vm)
            default:
                QRTransferResultView(result: result, delegate: viewModel)
            }
        case .error(let title, let message):
            let errorVMFactory = {
                ISQRErrorViewModel(
                    title: title,
                    message: message,
                    delegate: viewModel
                )
            }
            ErrorStateView(viewModelFactory: errorVMFactory)
        }
    }
}

@MainActor
protocol ViewLifeCycle {
    func onAppear() -> Void
    func onDisappear() -> Void
}
