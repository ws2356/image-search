//
//  TransferView.swift
//  ISFromMobile
//
//  Upload progress spinner; auto-navigates to CompletionFeature on success.
//
import SwiftUI
import ComposableArchitecture

struct TransferView: View {
    let store: StoreOf<TransferFeature>

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Sending...")
                .font(.headline)
            if store.progress > 0 {
                ProgressView(value: store.progress)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding()
        .task { store.send(.startTransfer) }
    }
}
