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
            
            VStack(spacing: 24) {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Text("Checking existing trust...")
                    .font(.headline)
                Text(store.payloadDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .task { store.send(.attemptRevisit) }
        }
    }
}
