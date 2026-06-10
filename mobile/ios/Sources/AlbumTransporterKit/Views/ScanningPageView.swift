import SwiftUI
import Common

struct ScanningPageView: View {
    let viewModel: ScanningPageViewModel

    var body: some View {
        LiveQRCodeScannerView(viewModel: viewModel) {
            QRScanTipBuilder.buildBackupSessionScanTips()
        }
    }
}
