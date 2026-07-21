//
//  ErrorView.swift
//  ISFromMobile
//
//  Full-screen error display with Retry and Cancel buttons.
//
import SwiftUI
import ComposableArchitecture

#if os(iOS)
struct ErrorView: View {
    let store: StoreOf<ErrorFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DesignSystem.Colors.warning)
                DSText(text: "Transfer Failed", style: .h2)
                DSText(
                    text: store.message,
                    style: .body,
                    color: DesignSystem.Colors.secondaryText
                )
                .multilineTextAlignment(.center)
                Spacer()
                HStack(spacing: DesignSystem.Spacing.lg) {
                    PrimaryButton(title: "Cancel", style: .secondary) {
                        store.send(.cancel)
                    }
                    PrimaryButton(title: "Try Again", style: .primary) {
                        store.send(.retry)
                    }
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .background(Color(.systemBackground))
        }
    }
}
#endif
