//
//  FontRegistration.swift
//  Common
//
//  Registers bundled custom fonts so SwiftUI `.custom("...")` calls resolve.
//  Created by agent on 2026-06-29.
//

import CoreText
import Foundation

public enum FontRegistration {
    /// Registers the bundled DM Sans and JetBrains Mono fonts for the current process.
    /// Call once at app launch; repeated calls are harmless.
    public static func registerCustomFonts() {
        let fontNames = [
            "DMSans-Regular.ttf",
            "DMSans-Italic.ttf",
            "JetBrainsMono-Regular.ttf",
            "JetBrainsMono-Medium.ttf",
            "JetBrainsMono-SemiBold.ttf",
            "JetBrainsMono-Bold.ttf",
        ]

        for fontName in fontNames {
            guard let fontURL = Bundle.module.url(forResource: fontName, withExtension: nil) else {
                continue
            }
            var error: Unmanaged<CFError>? = nil
            _ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            // Registration failures are non-fatal; the app falls back to system fonts.
        }
    }
}
