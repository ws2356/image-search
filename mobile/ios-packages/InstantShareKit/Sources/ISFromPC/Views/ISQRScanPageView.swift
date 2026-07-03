import SwiftUI
import Common

#if os(iOS)
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
#endif
