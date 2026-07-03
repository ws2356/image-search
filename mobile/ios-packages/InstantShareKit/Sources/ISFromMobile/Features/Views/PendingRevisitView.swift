//
//  PendingRevisitView.swift
//  ISFromMobile
//
//  Spinner with "Checking existing trust..." status.
//  No user action buttons — auto-navigates when revisit completes.
//
import SwiftUI
import ComposableArchitecture

struct PendingRevisitView: View {
    let store: StoreOf<PendingRevisitFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: DesignSystem.Spacing.xl) {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                    .tint(DesignSystem.Colors.primary)
                DSText(text: "Checking existing trust...", style: .h3)
                DSText(
                    text: store.payloadDescription,
                    style: .body,
                    color: DesignSystem.Colors.secondaryText
                )
                Spacer()
            }
            .padding(DesignSystem.Spacing.xl)
            .background(Color(.systemBackground))
            .task { store.send(.attemptRevisit) }
        }
    }
}
