//
//  AuthView.swift
//  ISFromMobile
//
//  Shows loading during automatic handshake+apply, then PIN entry.
//  On PIN submit → confirm → authCompleted. Upload is handled by TransferFeature.
//
import SwiftUI
import ComposableArchitecture
import Common

struct AuthView: View {
    let store: StoreOf<AuthFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                if store.isHandshaking {
                    // Loading state: handshake + apply in progress
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Connecting...")
                        .font(.headline)
                    Spacer()
                } else {
                    // PIN entry state
                    Spacer()
                    Text("Enter PIN")
                        .font(.title2.bold())
                    Text("Enter the 4-digit code shown on your Mac:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    @Perception.Bindable var model = store
                    
                    PinCodeInputView(pinCode: Binding(
                        get: { model.pinCode },
                        set: { store.send(.pinCodeChanged($0)) }
                    ))
                    .disabled(store.isProcessing)
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button(role: .cancel) {
                        store.send(.rejectPIN)
                    } label: {
                        Text("Cancel")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
            .padding()
            .task { store.send(.handshakeAndApply) }
        }
    }
}
