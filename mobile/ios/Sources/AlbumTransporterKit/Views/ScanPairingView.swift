import SwiftUI

struct ScanPairingView: View {
    let viewModel: PairingPageViewModel

    var body: some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            LiveQRCodeScannerScreen(
                status: viewModel.status,
                scannedQRCodeValue: viewModel.scannedQRCodeBinding,
                onStartPairing: {
                    Task {
                        await viewModel.beginPairingTapped()
                    }
                },
                onBack: {
                    Task {
                        await viewModel.backTapped()
                    }
                },
                onOpenSettings: viewModel.openSettingsTapped
            )
            .toolbar(.hidden, for: .navigationBar)
        } else {
            LiveQRCodeScannerScreen(
                status: viewModel.status,
                scannedQRCodeValue: viewModel.scannedQRCodeBinding,
                onStartPairing: {
                    Task {
                        await viewModel.beginPairingTapped()
                    }
                },
                onBack: {
                    Task {
                        await viewModel.backTapped()
                    }
                },
                onOpenSettings: viewModel.openSettingsTapped
            )
            .navigationBarHidden(true)
        }
        #else
        PairingStatusView(
            viewModel: viewModel
        )
        #endif
    }
}
