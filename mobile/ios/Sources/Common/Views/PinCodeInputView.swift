import SwiftUI
import UIKit

private final class HiddenPinTextField: UITextField {
    var onDigit: ((Character) -> Void)?
    var onDeleteBackward: (() -> Void)?

    override func deleteBackward() {
        onDeleteBackward?()
        super.deleteBackward()
    }
}

private struct PinCodeInputRepresentable: UIViewRepresentable {
    @Binding var isFocused: Bool
    var onDigit: (Character) -> Void
    var onDeleteBackward: () -> Void

    func makeUIView(context: Context) -> HiddenPinTextField {
        let textField = HiddenPinTextField()
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        textField.delegate = context.coordinator
        textField.isHidden = true
        return textField
    }

    func updateUIView(_ uiView: HiddenPinTextField, context: Context) {
        uiView.onDigit = onDigit
        uiView.onDeleteBackward = onDeleteBackward
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard !string.isEmpty else {
                return true
            }
            guard let pinField = textField as? HiddenPinTextField else {
                return false
            }
            for char in string where char.isNumber {
                pinField.onDigit?(char)
            }
            return false
        }
    }
}

public struct PinCodeInputView: View {
    public let onSubmit: (String) -> Void

    @State private var pinCharacters: [String] = Array(repeating: "", count: 4)
    @State private var isInputFocused = true

    public init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    public var body: some View {
        ZStack {
            PinCodeInputRepresentable(
                isFocused: $isInputFocused,
                onDigit: { digit in
                    guard let firstEmpty = pinCharacters.firstIndex(where: { $0.isEmpty }) else {
                        return
                    }
                    pinCharacters[firstEmpty] = String(digit)
                },
                onDeleteBackward: {
                    guard let lastFilled = pinCharacters.lastIndex(where: { !$0.isEmpty }) else {
                        return
                    }
                    pinCharacters[lastFilled] = ""
                }
            )
            .frame(width: 0, height: 0)

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    boxView(at: index)
                }
            }
            .onTapGesture {
                isInputFocused = true
            }
        }
        .onAppear {
            isInputFocused = true
        }
        .compatibleOnChange(of: pinCharacters) { _ in
            if pinCharacters.joined().count == 4 {
                onSubmit(pinCharacters.joined())
            }
        }
    }

    private func boxView(at index: Int) -> some View {
        let isActive = pinCharacters.joined().count == index

        return Text(pinCharacters[index])
            .font(.system(size: 32, weight: .heavy, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 60, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isActive ? 2 : 1
                    )
            )
    }
}
