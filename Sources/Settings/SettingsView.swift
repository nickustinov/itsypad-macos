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
    static let showG2Sync = true

    @ObservedObject var store: SettingsStore
    @ObservedObject private var tabStore = TabStore.shared
    @ObservedObject private var g2Engine = G2SyncEngine.shared
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
                    Text("Syncs scratch tabs and clipboard history (text only) across devices. File-backed tabs are not synced.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if store.icloudSync {
                        Text(lastSyncLabel)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .onReceive(timer) { now = $0 }
                    }
                }
                if Self.showG2Sync {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Even G2 sync", isOn: Binding(
                            get: { store.g2SyncEnabled },
                            set: { store.setG2Sync($0) }
                        ))
                        Text("Syncs scratch tabs with Even Realities G2 glasses.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if store.g2SyncEnabled {
                            g2StatusView
                        }
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

    @ViewBuilder
    private var g2StatusView: some View {
        switch g2Engine.state {
        case .disabled:
            EmptyView()
        case .pairing(let code):
            HStack(spacing: 6) {
                Text("Pairing code:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .fontWeight(.bold)
            }
            Text("Enter this code in the G2 app to connect.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        case .linked:
            HStack(spacing: 6) {
                Text("Connected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Unpair") {
                    store.setG2Sync(false)
                }
                .controlSize(.small)
            }
        }
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

            Section("Spacing") {
                HStack {
                    Text("Line spacing")
                    Spacer()
                    TextField("", value: $store.lineSpacing, format: .number.precision(.fractionLength(1)))
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $store.lineSpacing, in: 1.0...2.0, step: 0.1)
                        .labelsHidden()
                        .controlSize(.small)
                }
                HStack {
                    Text("Letter spacing")
                    Spacer()
                    TextField("", value: $store.letterSpacing, format: .number.precision(.fractionLength(1)))
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                    Stepper("", value: $store.letterSpacing, in: 0.0...5.0, step: 0.5)
                        .labelsHidden()
                        .controlSize(.small)
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

                Section("History") {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Auto-delete entries older than", selection: $store.clipboardAutoDelete) {
                            Text("Never").tag("never")
                            Text("1 hour").tag("1h")
                            Text("12 hours").tag("12h")
                            Text("1 day").tag("1d")
                            Text("7 days").tag("7d")
                            Text("14 days").tag("14d")
                            Text("30 days").tag("30d")
                        }
                        Text("Clipboard history stores up to 1,000 entries maximum.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
        .onChange(of: store.clipboardAutoDelete) {
            ClipboardStore.shared.pruneExpiredEntries()
        }
    }
}

