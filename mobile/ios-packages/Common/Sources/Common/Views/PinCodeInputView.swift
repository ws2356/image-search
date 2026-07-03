import SwiftUI
import UIKit

// TODO: This is a hacky solution. Consider adding an UI automation test.
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
        textField.isHidden = true
        textField.keyboardType = .numberPad
        textField.textContentType = .oneTimeCode
        textField.delegate = context.coordinator
        return textField
    }

    func updateUIView(_ uiView: HiddenPinTextField, context: Context) {
        uiView.onDigit = onDigit
        uiView.onDeleteBackward = onDeleteBackward
        // 关键改动：先判断当前实际焦点状态，避免陷入无限死循环
        if isFocused && !uiView.isFirstResponder {
            // 只有当 SwiftUI 想要它聚焦，且 UIKit 还没聚焦时，才调用 become
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isFocused && uiView.isFirstResponder {
            // 只有当 SwiftUI 想要它失焦，且 UIKit 还聚焦时，才调用 resign
            DispatchQueue.main.async {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isFocused: $isFocused)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var isFocused: Binding<Bool>
        
        init(isFocused: Binding<Bool>) {
            self.isFocused = isFocused
        }
        
        // --- 新增：监听 UIKit 文本框开始编辑 ---
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocused.wrappedValue {
                isFocused.wrappedValue = true
            }
        }
        
        // --- 新增：监听 UIKit 文本框结束编辑（比如键盘收起） ---
        func textFieldDidEndEditing(_ textField: UITextField) {
            if isFocused.wrappedValue {
                isFocused.wrappedValue = false
            }
        }
        
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
    private let pinCode: String
    @State private var isInputFocused = true
    
    private let onPinCodeChange: (String) -> Void

    public init(pinCode: String, onPinCodeChange: @escaping (String) -> Void) {
        self.pinCode = pinCode
        self.onPinCodeChange = onPinCodeChange
    }
    
    private var pinCharacters: [String] {
        var chars = Array(repeating: "", count: 4)
        let pinArray = Array(pinCode.map { String($0) })
        for i in 0..<min(pinArray.count, 4) {
            chars[i] = pinArray[i]
        }
        return chars
    }

    public var body: some View {
        ZStack {
            PinCodeInputRepresentable(
                isFocused: $isInputFocused,
                onDigit: { digit in
                    guard let firstEmpty = pinCharacters.firstIndex(where: { $0.isEmpty }) else {
                        return
                    }
                    if pinCode.count < 4 {
                        var newPinCode = pinCode
                        newPinCode.append(digit)
                        onPinCodeChange(newPinCode)
                    }
                },
                onDeleteBackward: {
                    guard let lastFilled = pinCharacters.lastIndex(where: { !$0.isEmpty }) else {
                        return
                    }
                    if !pinCode.isEmpty {
                        var newPinCode = pinCode
                        newPinCode.removeLast()
                        onPinCodeChange(newPinCode)
                    }
                }
            )
            .frame(width: 0, height: 0)

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    boxView(at: index)
                        .onTapGesture {
                            isInputFocused = true
                        }
                }
            }
        }
        .onAppear {
            isInputFocused = true
        }
        .compatibleOnChange(of: pinCode) { _ in
            if pinCode.isEmpty {
                isInputFocused = true
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
