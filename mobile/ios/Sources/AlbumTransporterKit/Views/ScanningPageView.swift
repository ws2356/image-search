import SwiftUI

struct ScanningPageView: View {
    let viewModel: ScanningPageViewModel

    var body: some View {
        let scannerView = LiveQRCodeScannerView(
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
        if #available(iOS 16.0, *) {
            scannerView
            .toolbar(.hidden, for: .navigationBar)
        } else {
            scannerView
            .navigationBarHidden(true)
        }
    }
}
