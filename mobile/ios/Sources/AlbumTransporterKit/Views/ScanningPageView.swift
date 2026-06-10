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
                    
                    Text("Quickly share from your PC:")
                        .font(.system(size: 15, weight: .semibold))
                    Text("        1. Download and install AuSearch from https://aurora.boldman.net")
                    Text("        2. (Optionally) Enable InstantShare extension: System Settings > General > Login Items & Extensions > Sharing > InstantShare.")
                    Text("        3. Right click text or file, then ‘Share > InstantShare’ to show the QR code.")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}
