import SwiftUI
import AppKit

extension Color {
    /// Ivory in dark mode, ebony in light mode — always opposite the current
    /// system theme. A monochrome accent that doesn't compete with the app
    /// icon. Pairs with `furwallAccentText` for labels that sit on top of an
    /// accent fill.
    static let furwallAccent = Color(NSColor(name: "FurwallAccent", dynamicProvider: { appearance in
        appearance.isDark
            ? NSColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1.0)  // ivory
            : NSColor(red: 0.13, green: 0.11, blue: 0.09, alpha: 1.0)  // ebony
    }))

    /// Inverse of `furwallAccent` — for text/glyphs sitting ON top of an
    /// accent fill. Ebony in dark mode, ivory in light mode.
    static let furwallAccentText = Color(NSColor(name: "FurwallAccentText", dynamicProvider: { appearance in
        appearance.isDark
            ? NSColor(red: 0.13, green: 0.11, blue: 0.09, alpha: 1.0)  // ebony
            : NSColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1.0)  // ivory
    }))
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [
            .darkAqua, .vibrantDark,
            .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark,
        ]) != nil
    }
}
