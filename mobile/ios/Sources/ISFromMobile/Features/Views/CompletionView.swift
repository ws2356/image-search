//
//  CompletionView.swift
//  ISFromMobile
//
//  Success confirmation with "Done" button that exits the share extension.
//
import SwiftUI
import ComposableArchitecture

struct CompletionView: View {
    let store: StoreOf<CompletionFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Sent!")
                    .font(.title2.bold())
                Text("\(store.payloadDescription.capitalized) delivered to your Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.send(.done)
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
