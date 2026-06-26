//
//  ErrorView.swift
//  ISFromMobile
//
//  Full-screen error display with Retry and Cancel buttons.
//
import SwiftUI
import ComposableArchitecture

struct ErrorView: View {
    let store: StoreOf<ErrorFeature>

    var body: some View {
        WithPerceptionTracking {
            
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Transfer Failed")
                    .font(.title2.bold())
                Text(store.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        store.send(.cancel)
                    } label: {
                        Text("Cancel")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        store.send(.retry)
                    } label: {
                        Text("Try Again")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}
