//
//  CompletionView.swift
//  ISFromMobile
//
//  Success confirmation with "Done" button that exits the share extension.
//  Uses primary blue (#3b7dfa) for the Done button (fixes color inconsistency).
//
import SwiftUI
import ComposableArchitecture

struct CompletionView: View {
    let store: StoreOf<CompletionFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()
                // Success icon with concentric ring placeholder
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DesignSystem.Colors.success)
                DSText(text: "Sent!", style: .h2)
                DSText(
                    text: "\(store.payloadDescription.capitalized) delivered to your Mac",
                    style: .body,
                    color: DesignSystem.Colors.secondaryText
                )
                Spacer()
                PrimaryButton(title: "Done", style: .primary) {
                    store.send(.done)
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .background(Color(.systemBackground))
        }
    }
}
