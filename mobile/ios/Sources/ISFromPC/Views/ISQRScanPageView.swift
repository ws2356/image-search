import SwiftUI
import Common

struct ISQRScanPageView: View {
    @StateObject private var viewModel: ISQRScanViewModel
    
    init(delegate: QRScanDelegate) {
        self._viewModel = StateObject(wrappedValue: .init(delegate: delegate))
    }

    var body: some View {
        LiveQRCodeScannerView(viewModel: viewModel) {
            QRScanTipBuilder.buildInstantShareScanTips()
        }
    }
}
