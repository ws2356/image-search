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

#if os(iOS)
struct AuthView: View {
    let store: StoreOf<AuthFeature>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: DesignSystem.Spacing.xl) {
                if store.isHandshaking {
                    // Loading state: handshake + apply in progress
                    LoadingSpinner(message: "Connecting...")
                } else {
                    // PIN entry state
                    Spacer()
                    DSText(text: "Enter PIN", style: .h2)
                    DSText(
                        text: "Enter the 4-digit code shown on your Mac:",
                        style: .body,
                        color: DesignSystem.Colors.secondaryText
                    )

                    PinCodeInputView(pinCode: store.pinCode) { newPinCode in
                        store.send(.pinCodeChanged(newPinCode))
                    }
                    .disabled(store.isProcessing)

                    if let error = store.errorMessage {
                        DSText(text: error, style: .caption, color: DesignSystem.Colors.error)
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: "Cancel", style: .secondary) {
                        store.send(.rejectPIN)
                    }
                    Spacer()
                }
            }
            .padding(DesignSystem.Spacing.xl)
            .background(Color(.systemBackground))
            .task { store.send(.handshakeAndApply) }
        }
    }
}
#endif
