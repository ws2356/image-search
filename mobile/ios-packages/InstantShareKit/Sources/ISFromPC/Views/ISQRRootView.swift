import SwiftUI
import Common

#if os(iOS)
public struct ISQRRootView: View {
    @StateObject private var viewModel: ISQRRootViewModel
    let navigator: Navigator

    public init(qrPayload: QRClaimPayload, navigator: Navigator) {
        _viewModel = StateObject(wrappedValue: ISQRRootViewModel(
            initialState: .claiming,
            qrClaimPayload: qrPayload,
            navigator: navigator
        ))
        self.navigator = navigator
    }

    public init(navigator: Navigator) {
        _viewModel = StateObject(wrappedValue: ISQRRootViewModel(
            initialState: .scan,
            navigator: navigator
        ))
        self.navigator = navigator
    }

    public var body: some View {
        navigationContainer
            .onAppear {
                configureNavigationBar()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
    }
    
    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
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
            if let payload = viewModel.qrClaimPayload {
                QRClaimView(qrClaimPayload: payload, delegate: viewModel)
            } else {
                EmptyView()
            }
        case .result(let result):
            let vm = makeMultiFileViewModel(for: result, delegate: viewModel)
            MultiFileReceiveView(viewModel: vm)
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
private extension ISQRRootView {
    func makeMultiFileViewModel(for result: QRClaimResult, delegate: ISQRDeliverDelegate) -> MultiFileReceiveViewModel {
        switch result {
        case .multiFile(let manifest, let host, let tlsPort, let sessionId, let correlationID):
            return MultiFileReceiveViewModel(
                manifest: manifest,
                host: host,
                tlsPort: tlsPort,
                sessionId: sessionId,
                correlationID: correlationID,
                delegate: delegate
            )
        default:
            return MultiFileReceiveViewModel(singleResult: result, delegate: delegate)
        }
    }
}
#endif

@MainActor
protocol ViewLifeCycle {
    func onAppear() -> Void
    func onDisappear() -> Void
}
