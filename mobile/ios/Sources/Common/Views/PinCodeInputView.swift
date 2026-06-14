import SwiftUI

public struct PinCodeInputView: View {
    public let onSubmit: (String) -> Void

    @State private var pinCharacters: [String] = Array(repeating: "", count: 4)
    @FocusState private var focusedField: Int?

    public init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                TextField("", text: Binding(
                    get: { pinCharacters[index] },
                    set: { handlePinInput($0, at: index) }
                ))
                    .font(.system(size: 32, weight: .heavy, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .frame(width: 60, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                focusedField == index ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: focusedField == index ? 2 : 1
                            )
                    )
                    .focused($focusedField, equals: index)
            }
        }
        .onAppear {
            focusedField = 0
        }
        .compatibleOnChange(of: pinCharacters) { _ in
            if pinCharacters.joined().count == 4 {
                onSubmit(pinCharacters.joined())
            }
        }
    }

    private func handlePinInput(_ newValue: String, at index: Int) {
        let digits = newValue.filter(\.isNumber)

        if digits.isEmpty {
            pinCharacters[index] = ""
            return
        }

        if digits.count == 1 {
            pinCharacters[index] = String(digits)
            if index < 3 {
                focusedField = index + 1
            }
        } else {
            let remaining = Array(digits.prefix(4 - index))
            for (i, char) in remaining.enumerated() {
                pinCharacters[index + i] = String(char)
            }
            focusedField = min(index + remaining.count, 3)
        }
    }
}
