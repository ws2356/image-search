//
//  DesignSystemText.swift
//  ISFromMobile
//
//  Reusable text components with consistent typography hierarchy.
//
import SwiftUI

#if os(iOS)
/// Heading text using design system typography
struct DSText: View {
    let text: String
    let style: TextStyle
    var color: Color? = nil

    enum TextStyle {
        case h1, h2, h3, h4, body, caption, caption2
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color ?? defaultColor)
    }

    private var font: Font {
        switch style {
        case .h1: return DesignSystem.Typography.h1
        case .h2: return DesignSystem.Typography.h2
        case .h3: return DesignSystem.Typography.h3
        case .h4: return DesignSystem.Typography.h4
        case .body: return DesignSystem.Typography.body
        case .caption: return DesignSystem.Typography.caption
        case .caption2: return DesignSystem.Typography.caption2
        }
    }

    private var defaultColor: Color {
        switch style {
        case .caption, .caption2: return DesignSystem.Colors.secondaryText
        default: return DesignSystem.Colors.foreground
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        DSText(text: "Heading 1", style: .h1)
        DSText(text: "Heading 2", style: .h2)
        DSText(text: "Heading 3", style: .h3)
        DSText(text: "Heading 4", style: .h4)
        DSText(text: "Body text", style: .body)
        DSText(text: "Caption text", style: .caption)
        DSText(text: "Small caption", style: .caption2)
        DSText(text: "Primary colored", style: .h3, color: DesignSystem.Colors.primary)
    }
    .padding()
    .background(Color(.systemBackground))
}
#endif
