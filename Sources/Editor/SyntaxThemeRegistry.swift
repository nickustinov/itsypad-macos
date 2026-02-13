struct SyntaxThemeDefinition {
    let id: String
    let displayName: String
    let darkResource: String
    let lightResource: String
}

enum SyntaxThemeRegistry {
    static let themes: [SyntaxThemeDefinition] = [
        .init(id: "atom-one", displayName: "Atom One", darkResource: "atom-one-dark.min", lightResource: "atom-one-light.min"),
        .init(id: "catppuccin", displayName: "Catppuccin", darkResource: "catppuccin-mocha.min", lightResource: "catppuccin-latte.min"),
        .init(id: "gruvbox", displayName: "Gruvbox", darkResource: "gruvbox-dark.min", lightResource: "gruvbox-light.min"),
        .init(id: "intellij", displayName: "IntelliJ / Darcula", darkResource: "androidstudio.min", lightResource: "intellij-light.min"),
        .init(id: "itsypad", displayName: "Itsypad", darkResource: "itsypad-dark.min", lightResource: "itsypad-light.min"),
        .init(id: "solarized", displayName: "Solarized", darkResource: "solarized-dark.min", lightResource: "solarized-light.min"),
        .init(id: "stackoverflow", displayName: "Stack Overflow", darkResource: "stackoverflow-dark.min", lightResource: "stackoverflow-light.min"),
        .init(id: "tokyo-night", displayName: "Tokyo Night", darkResource: "tokyo-night-dark.min", lightResource: "tokyo-night-light.min"),
        .init(id: "vs", displayName: "Visual Studio", darkResource: "vs2015.min", lightResource: "vs.min"),
    ]

    static func cssResource(for themeId: String, isDark: Bool) -> String {
        let def = themes.first { $0.id == themeId } ?? themes.first { $0.id == "itsypad" }!
        return isDark ? def.darkResource : def.lightResource
    }
}
