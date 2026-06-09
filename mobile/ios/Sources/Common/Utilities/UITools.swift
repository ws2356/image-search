//
//  UITools.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/10.
//
import SwiftUI

extension View {
    @ViewBuilder
    public func compatibleScrollBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    public func compatibleKerning(_ value: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.kerning(value)
        } else {
            self
        }
    }

    @ViewBuilder
    public func compatibleTracking(_ value: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.tracking(value)
        } else {
            self
        }
    }

    @ViewBuilder
    public func compatibleOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

extension Color {
    public init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public func heroCircle(icon: String, gradient: [Color], size: CGFloat = 100) -> some View {
    ZStack {
        Circle()
            .fill(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .shadow(color: gradient.first?.opacity(0.4) ?? .clear, radius: 16, y: 8)

        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
    }
}

public struct ActionButton: View {
    let title: String
    var icon: String? = nil
    let style: ActionButtonStyle
    var height: CGFloat? = nil
    let action: () -> Void
    
    public init(title: String, icon: String? = nil, style: ActionButtonStyle, height: CGFloat? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.height = height
        self.action = action
    }

    public enum ActionButtonStyle {
        case primary, secondary, cancelSecondary, destructive, plain
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.system(size: style == .plain ? 15 : 17, weight: style == .plain ? .medium : .semibold))
            }
            .frame(maxWidth: style == .plain ? nil : .infinity)
            .frame(height: height ?? defaultHeight)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: style == .plain ? 8 : 14))
            .overlay(borderOverlay)
        }
        .buttonStyle(.plain)
    }

    private var defaultHeight: CGFloat {
        style == .plain ? 36 : 52
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return Color(hex: 0x007AFF)
        case .cancelSecondary: return Color(hex: 0xFF453A)
        case .destructive: return Color(hex: 0xFF453A)
        case .plain: return Color(hex: 0x007AFF)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return Color(hex: 0x007AFF)
        case .secondary: return Color.white
        case .cancelSecondary: return Color.white
        case .destructive: return Color(hex: 0xFFF1F0)
        case .plain: return .clear
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if style == .secondary || style == .cancelSecondary {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: 0xE5E5EA), lineWidth: 1.5)
        }
    }
}

// MARK: - Navigation Bar Styling

extension View {
    @ViewBuilder
    public func appNavigationBar(title: String) -> some View {
        if #available(iOS 16.0, *) {
            self
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.97, blue: 1.0),
                            Color.white,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    for: .navigationBar
                )
                .toolbarColorScheme(.light, for: .navigationBar)
        } else {
            self
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

