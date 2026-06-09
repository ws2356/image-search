import SwiftUI

struct ScanningPageView: View {
    let viewModel: ScanningPageViewModel

    var body: some View {
        if #available(iOS 16.0, *) {
            LiveQRCodeScannerView(
                onScanComplete: { scannedValue in
                    Task {
                        await viewModel.onQRScanned(scannedValue: scannedValue)
                    }
                },
                onScanFailure: {
                    Task {
                        await viewModel.scannerFailed()
                    }
                },
                onBack: {
                    Task {

                        await viewModel.backTapped()
                    }
                },
                onOpenSettings: {
                    Task {
                        await viewModel.openSettingsTapped()
                    }
                }
            )
            .toolbar(.hidden, for: .navigationBar)
        } else {
            LiveQRCodeScannerView(
                onScanComplete: { scannedValue in
                    Task {
                        await viewModel.onQRScanned(scannedValue: scannedValue)
                    }
                },
                onScanFailure: {
                    Task {
                        await viewModel.scannerFailed()
                    }
                },
                onBack: {
                    Task {
                        await viewModel.backTapped()
                    }
                },
                onOpenSettings: {
                    Task {
                        await viewModel.openSettingsTapped()
                    }
                }
            )
            .navigationBarHidden(true)
        }
    }
}
