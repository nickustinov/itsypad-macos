import SwiftUI
import AppKit

/// Native macOS colors for the tab bar, with optional overrides
enum TabBarColors {
    // MARK: - Tab Bar Background

    static var barBackground: Color {
        if let color = BonsplitTheme.shared.barBackground { return Color(nsColor: color) }
        return Color(nsColor: .windowBackgroundColor)
    }

    static var barMaterial: Material {
        .bar
    }

    // MARK: - Tab States

    static var activeTabBackground: Color {
        if let color = BonsplitTheme.shared.activeTabBackground { return Color(nsColor: color) }
        return Color(nsColor: .controlBackgroundColor)
    }

    static var hoveredTabBackground: Color {
        if let color = BonsplitTheme.shared.activeTabBackground {
            return Color(nsColor: color).opacity(0.5)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    static var inactiveTabBackground: Color {
        if let color = BonsplitTheme.shared.activeTabBackground {
            return Color(nsColor: color.blended(withFraction: 0.06, of: .white) ?? color)
        }
        return .clear
    }

    // MARK: - Text Colors

    static var activeText: Color {
        Color(nsColor: .labelColor)
    }

    static var inactiveText: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    // MARK: - Borders & Indicators

    static var separator: Color {
        if let color = BonsplitTheme.shared.separator { return Color(nsColor: color) }
        return Color(nsColor: .separatorColor)
    }

    static var dropIndicator: Color {
        Color.accentColor
    }

    static var focusRing: Color {
        Color.accentColor.opacity(0.5)
    }

    static var dirtyIndicator: Color {
        Color(nsColor: .labelColor).opacity(0.6)
    }

    // MARK: - Shadows

    static var tabShadow: Color {
        Color.black.opacity(0.08)
    }
}
