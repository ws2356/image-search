import SwiftUI
import Common

struct ScanningPageView: View {
    let viewModel: ScanningPageViewModel

    var body: some View {
        GeometryReader { geometry in
            LiveQRCodeScannerView(viewModel: viewModel) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start a QR code based backup session on your pc:")
                        .font(.system(size: 15, weight: .semibold))
                    Text("        1. Open https://aurora.boldman.net on your PC browser then install and launch AuSearch.")
                    Text("        2. Click 'Add Folder'.")
                    Text("        3. Select 'Mobile Device'.")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.60))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 24, 32))
            }
        }
    }
}
