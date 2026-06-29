import SwiftUI
import CoreText

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum DesignSystem {

    enum Colors {
        static let background = Color.white
        static let foreground = Color.black
        static let primary = Color(hex: 0x2563EB)
        static let cardBackground = Color(hex: 0xF2F2F7)
        static let secondaryText = Color(hex: 0x8E8E93)
        static let success = Color(hex: 0x34C759)
        static let error = Color(hex: 0xFF453A)
        static let warning = Color(hex: 0xFF9F0A)
        static let border = Color.black.opacity(0.1)
        static let selectedHighlight = Color(hex: 0x2563EB).opacity(0.1)

        static let slate900 = Color(hex: 0x0F172A)
        static let slate700 = Color(hex: 0x334155)
        static let slate400 = Color(hex: 0x94A3B8)
        static let slate200 = Color(hex: 0xE2E8F0)
        static let slate100 = Color(hex: 0xF1F5F9)
        static let slate50 = Color(hex: 0xF8FAFC)
        static let blue50 = Color(hex: 0xEFF6FF)
        static let blue600 = Color(hex: 0x2563EB)
        static let emerald600 = Color(hex: 0x059669)
    }

    enum Typography {
        static let h1 = Font.dmSans(size: 24, weight: .bold)
        static let h2 = Font.dmSans(size: 20, weight: .bold)
        static let h3 = Font.dmSans(size: 18, weight: .semibold)
        static let h4 = Font.dmSans(size: 16, weight: .medium)
        static let body = Font.dmSans(size: 15, weight: .regular)
        static let caption = Font.dmSans(size: 13, weight: .regular)
        static let caption2 = Font.dmSans(size: 11, weight: .regular)
        static let captionBold = Font.dmSans(size: 15, weight: .bold)
        static let captionMedium = Font.dmSans(size: 13, weight: .medium)
        static let monoBody = Font.jetBrainsMono(size: 14, weight: .regular)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum CornerRadius {
        static let card: CGFloat = 10
        static let button: CGFloat = 14
        static let chip: CGFloat = 8
        static let xl: CGFloat = 16
    }
}

extension Font {
    static func dmSans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("DM Sans", size: size).weight(weight)
    }

    static func jetBrainsMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let familyName = "JetBrains Mono"
        let availableFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        if availableFamilies.contains(familyName) {
            return .custom(familyName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
