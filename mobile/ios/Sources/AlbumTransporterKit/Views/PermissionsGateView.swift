import SwiftUI

struct PermissionsGateView: View {
    let onStartPreflight: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    heroCircle(icon: "lock.shield.fill", gradient: [Color(hex: 0x007AFF), Color(hex: 0x0055D4)])

                    Text("Backup preflight")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text("Preparing backup...")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(Color(hex: 0x007AFF))
                        .padding(.top, 6)

                    Text("Checking media access, battery status, and backup cleanup preference. Continue in each prompt to begin transfer automatically.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .compatibleScrollBounceBasedOnSize()
        .task {
            onStartPreflight()
        }
    }
}
