//
//  TransferView.swift
//  ISFromMobile
//
//  Upload progress spinner; auto-navigates to CompletionFeature on success.
//
import SwiftUI
import ComposableArchitecture

#if os(iOS)
struct TransferView: View {
    let store: StoreOf<TransferFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(DesignSystem.Colors.primary)
                DSText(text: "Sending...", style: .h3)
                if store.progress > 0 {
                    TransferProgress(progress: Double(store.progress))
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                }
                Spacer()
            }
            .padding(DesignSystem.Spacing.xl)
            .background(Color(.systemBackground))
            .task { store.send(.startTransfer) }
        }
    }
}
#endif
