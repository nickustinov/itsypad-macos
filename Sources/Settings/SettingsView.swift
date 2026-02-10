import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case editor
    case appearance
    case clipboard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .editor: return "Editor"
        case .appearance: return "Appearance"
        case .clipboard: return "Clipboard"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .editor: return "square.and.pencil"
        case .appearance: return "paintbrush"
        case .clipboard: return "paperclip"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label, systemImage: tab.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 170)
            .background(.ultraThinMaterial)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(store: store)
                case .editor:
                    EditorSettingsView(store: store)
                case .appearance:
                    AppearanceSettingsView(store: store)
                case .clipboard:
                    ClipboardSettingsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 400)
        .onAppear {
            store.syncLaunchAtLoginStatus()
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var tabStore = TabStore.shared
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $store.launchAtLogin)
                ShortcutRecorderView(
                    label: "Show Itsypad",
                    shortcut: $store.shortcut,
                    shortcutKeys: Binding(
                        get: { store.shortcutKeys },
                        set: { store.shortcutKeys = $0 }
                    )
                )
                Toggle("Show in dock", isOn: $store.showInDock)
                    .disabled(!store.showInMenuBar)
                Toggle("Show in menu bar", isOn: $store.showInMenuBar)
                    .disabled(!store.showInDock)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("iCloud sync", isOn: Binding(
                        get: { store.icloudSync },
                        set: { store.setICloudSync($0) }
                    ))
                    Text("Only syncs scratch tabs and their content. Tabs backed by files on disk are not transferred.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if store.icloudSync {
                        Text(lastSyncLabel)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .onReceive(timer) { now = $0 }
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Source code")
                    Spacer()
                    Link("GitHub", destination: URL(string: githubURL)!)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var lastSyncLabel: String {
        guard let date = tabStore.lastICloudSync else {
            return "Not yet synced"
        }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 {
            return "Last synced: just now"
        } else if seconds < 60 {
            return "Last synced: \(seconds)s ago"
        } else {
            let minutes = seconds / 60
            return "Last synced: \(minutes) min ago"
        }
    }
}

struct EditorSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Word wrap", isOn: $store.wordWrap)
                Toggle("Show line numbers", isOn: $store.showLineNumbers)
                Toggle("Highlight current line", isOn: $store.highlightCurrentLine)
                Toggle("Clickable links", isOn: $store.clickableLinks)
            }

            Section("Indentation") {
                Toggle("Indent using spaces", isOn: $store.indentUsingSpaces)
                Picker("Tab width", selection: $store.tabWidth) {
                    ForEach(1...8, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
            }

            Section("Lists") {
                Toggle("Bullet lists", isOn: $store.bulletListsEnabled)
                Toggle("Numbered lists", isOn: $store.numberedListsEnabled)
                Toggle("Checklists", isOn: $store.checklistsEnabled)
            }

        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $store.appearanceOverride) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Syntax theme", selection: $store.syntaxTheme) {
                    ForEach(SyntaxThemeRegistry.themes, id: \.id) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
            }

            Section("Font") {
                Picker("Font", selection: $store.editorFontName) {
                    ForEach(SettingsStore.availableFonts, id: \.name) { font in
                        Text(font.displayName).tag(font.name)
                    }
                }

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: $store.editorFontSize, format: .number)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $store.editorFontSize, in: 8...36, step: 1)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ClipboardSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable clipboard manager", isOn: $store.clipboardEnabled)
                if store.clipboardEnabled {
                    ShortcutRecorderView(
                        label: "Show clipboard",
                        shortcut: $store.clipboardShortcut,
                        shortcutKeys: Binding(
                            get: { store.clipboardShortcutKeys },
                            set: { store.clipboardShortcutKeys = $0 }
                        )
                    )
                }
            }

            if store.clipboardEnabled {
                Section("Behaviour") {
                    Picker("Default action", selection: $store.clipboardClickAction) {
                        Text("Copy to clipboard").tag("copy")
                        Text("Paste into active app").tag("paste")
                    }
                }

                Section("Display") {
                    Picker("View mode", selection: $store.clipboardViewMode) {
                        Text("Grid").tag("grid")
                        Text("Panels").tag("panels")
                    }
                    HStack {
                        Text("Preview lines")
                        Spacer()
                        TextField("", value: $store.clipboardPreviewLines, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Stepper("", value: $store.clipboardPreviewLines, in: 1...20)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    HStack {
                        Text("Font size")
                        Spacer()
                        TextField("", value: $store.clipboardFontSize, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Stepper("", value: $store.clipboardFontSize, in: 8...24, step: 1)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

