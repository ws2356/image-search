import SwiftUI
import Common

struct GenericQRScanView: View {
    let viewModel: GenericQRScanPageViewModel

    var body: some View {
        LiveQRCodeScannerView(viewModel: viewModel) {
            QRScanTipBuilder.buildGenericQRScanTips()
        }
    }
}
