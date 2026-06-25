//
//  AuthView.swift
//  ISFromMobile
//
//  PIN input, error caption, Cancel button.
//
import SwiftUI
import ComposableArchitecture
import Common

struct AuthView: View {
    let store: StoreOf<AuthFeature>

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Enter PIN")
                .font(.title2.bold())
            Text("Enter the 4-digit code shown on your Mac:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PinCodeInputView(onSubmit: { pinCode in
                store.send(.pinCodeChanged(pinCode))
                store.send(.confirmPIN)
            })
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
        .padding()
    }
}
