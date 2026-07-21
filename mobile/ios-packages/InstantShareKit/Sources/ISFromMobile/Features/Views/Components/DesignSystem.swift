//
//  DesignSystem.swift
//  ISFromMobile
//
//  Centralized design tokens for the instant-share UI.
//  All colors, typography, and spacing constants live here.
//  Light mode palette — dark mode support deferred.
//
import SwiftUI

#if os(iOS)
// Local Color(hex:) initializer (also available via Common module)
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

    // MARK: - Colors (Light Mode)

    enum Colors {
        /// White background
        static let background = Color.white
        /// Dark foreground text
        static let foreground = Color.black
        /// Primary blue accent (#3b7dfa)
        static let primary = Color(hex: 0x3B7DFA)
        /// Card background (light gray)
        static let cardBackground = Color(hex: 0xF2F2F7)
        /// Secondary/muted text (system gray)
        static let secondaryText = Color(hex: 0x8E8E93)
        /// Success green
        static let success = Color(hex: 0x34C759)
        /// Error red
        static let error = Color(hex: 0xFF453A)
        /// Warning orange
        static let warning = Color(hex: 0xFF9F0A)
        /// Subtle border
        static let border = Color.black.opacity(0.1)
        /// Device selected highlight
        static let selectedHighlight = Color(hex: 0x3B7DFA).opacity(0.1)
    }

    // MARK: - Typography

    enum Typography {
        static let h1 = Font.dmSans(size: 24, weight: .bold)
        static let h2 = Font.dmSans(size: 20, weight: .bold)
        static let h3 = Font.dmSans(size: 18, weight: .semibold)
        static let h4 = Font.dmSans(size: 16, weight: .medium)
        static let body = Font.dmSans(size: 15, weight: .regular)
        static let caption = Font.dmSans(size: 13, weight: .regular)
        static let caption2 = Font.dmSans(size: 11, weight: .regular)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let card: CGFloat = 10
        static let button: CGFloat = 14
        static let chip: CGFloat = 8
    }
}

// MARK: - DM Sans Font Extension

extension Font {
    static func dmSans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // DM Sans is registered in the app; fall back to system font if unavailable
        .custom("DM Sans", size: size).weight(weight)
    }
}
#endif
