import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case editor
    case appearance
    case clipboard
    case labs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return String(localized: "settings.tab.general", defaultValue: "General")
        case .editor: return String(localized: "settings.tab.editor", defaultValue: "Editor")
        case .appearance: return String(localized: "settings.tab.appearance", defaultValue: "Appearance")
        case .clipboard: return String(localized: "settings.tab.clipboard", defaultValue: "Clipboard")
        case .labs: return String(localized: "settings.tab.labs", defaultValue: "Labs")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .editor: return "square.and.pencil"
        case .appearance: return "paintbrush"
        case .clipboard: return "paperclip"
        case .labs: return "flask"
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
                case .labs:
                    LabsSettingsView(store: store)
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
                Toggle(String(localized: "settings.general.open_at_login", defaultValue: "Open at login"), isOn: $store.launchAtLogin)
                ShortcutRecorderView(
                    label: String(localized: "settings.general.show_itsypad", defaultValue: "Show Itsypad"),
                    shortcut: $store.shortcut,
                    shortcutKeys: Binding(
                        get: { store.shortcutKeys },
                        set: { store.shortcutKeys = $0 }
                    )
                )
                Toggle(String(localized: "settings.general.show_in_dock", defaultValue: "Show in dock"), isOn: $store.showInDock)
                    .disabled(!store.showInMenuBar)
                Toggle(String(localized: "settings.general.show_in_menu_bar", defaultValue: "Show in menu bar"), isOn: $store.showInMenuBar)
                    .disabled(!store.showInDock)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "settings.general.icloud_sync", defaultValue: "iCloud sync"), isOn: Binding(
                        get: { store.icloudSync },
                        set: { store.setICloudSync($0) }
                    ))
                    Text(String(localized: "settings.general.icloud_sync_description", defaultValue: "Syncs scratch tabs and clipboard history (text only) across devices. File-backed tabs are not synced."))
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

            Section(String(localized: "settings.general.about", defaultValue: "About")) {
                HStack {
                    Text(String(localized: "settings.general.version", defaultValue: "Version"))
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(String(localized: "settings.general.source_code", defaultValue: "Source code"))
                    Spacer()
                    Link(String(localized: "settings.general.github", defaultValue: "GitHub"), destination: URL(string: githubURL)!)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var lastSyncLabel: String {
        guard let date = tabStore.lastICloudSync else {
            return String(localized: "settings.general.sync_not_yet", defaultValue: "Not yet synced")
        }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 {
            return String(localized: "settings.general.sync_just_now", defaultValue: "Last synced: just now")
        } else if seconds < 60 {
            return String(localized: "settings.general.sync_seconds_ago", defaultValue: "Last synced: \(seconds)s ago")
        } else {
            let minutes = seconds / 60
            return String(localized: "settings.general.sync_minutes_ago", defaultValue: "Last synced: \(minutes) min ago")
        }
    }
}

struct LabsSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject private var g2Engine = G2SyncEngine.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "settings.labs.g2_sync", defaultValue: "Even G2 sync"), isOn: Binding(
                        get: { store.g2SyncEnabled },
                        set: { store.setG2Sync($0) }
                    ))
                    Text(String(localized: "settings.labs.g2_sync_description", defaultValue: "Syncs scratch tabs with Even Realities G2 glasses."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if store.g2SyncEnabled {
                        g2StatusView
                    }
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
                Text(String(localized: "settings.labs.pairing_code", defaultValue: "Pairing code:"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .fontWeight(.bold)
            }
            Text(String(localized: "settings.labs.pairing_hint", defaultValue: "Enter this code in the G2 app to connect."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        case .linked:
            HStack(spacing: 6) {
                Text(String(localized: "settings.labs.connected", defaultValue: "Connected"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(String(localized: "settings.labs.unpair", defaultValue: "Unpair")) {
                    store.setG2Sync(false)
                }
                .controlSize(.small)
            }
        }
    }
}

struct EditorSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.editor.word_wrap", defaultValue: "Word wrap"), isOn: $store.wordWrap)
                Toggle(String(localized: "settings.editor.show_line_numbers", defaultValue: "Show line numbers"), isOn: $store.showLineNumbers)
                Toggle(String(localized: "settings.editor.highlight_current_line", defaultValue: "Highlight current line"), isOn: $store.highlightCurrentLine)
                Toggle(String(localized: "settings.editor.clickable_links", defaultValue: "Clickable links"), isOn: $store.clickableLinks)
            }

            Section(String(localized: "settings.editor.indentation", defaultValue: "Indentation")) {
                Toggle(String(localized: "settings.editor.indent_using_spaces", defaultValue: "Indent using spaces"), isOn: $store.indentUsingSpaces)
                Picker(String(localized: "settings.editor.tab_width", defaultValue: "Tab width"), selection: $store.tabWidth) {
                    ForEach(1...8, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
            }

            Section(String(localized: "settings.editor.spacing", defaultValue: "Spacing")) {
                HStack {
                    Text(String(localized: "settings.editor.line_spacing", defaultValue: "Line spacing"))
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
                    Text(String(localized: "settings.editor.letter_spacing", defaultValue: "Letter spacing"))
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

            Section(String(localized: "settings.editor.lists", defaultValue: "Lists")) {
                Toggle(String(localized: "settings.editor.bullet_lists", defaultValue: "Bullet lists"), isOn: $store.bulletListsEnabled)
                Toggle(String(localized: "settings.editor.numbered_lists", defaultValue: "Numbered lists"), isOn: $store.numberedListsEnabled)
                Toggle(String(localized: "settings.editor.checklists", defaultValue: "Checklists"), isOn: $store.checklistsEnabled)
            }

        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section(String(localized: "settings.appearance.theme", defaultValue: "Theme")) {
                Picker(String(localized: "settings.appearance.appearance", defaultValue: "Appearance"), selection: $store.appearanceOverride) {
                    Text(String(localized: "settings.appearance.system", defaultValue: "System")).tag("system")
                    Text(String(localized: "settings.appearance.light", defaultValue: "Light")).tag("light")
                    Text(String(localized: "settings.appearance.dark", defaultValue: "Dark")).tag("dark")
                }
                Picker(String(localized: "settings.appearance.syntax_theme", defaultValue: "Syntax theme"), selection: $store.syntaxTheme) {
                    ForEach(SyntaxThemeRegistry.themes, id: \.id) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
            }

            Section(String(localized: "settings.appearance.font", defaultValue: "Font")) {
                Picker(String(localized: "settings.appearance.font", defaultValue: "Font"), selection: $store.editorFontName) {
                    ForEach(SettingsStore.availableFonts, id: \.name) { font in
                        Text(font.displayName).tag(font.name)
                    }
                }

                HStack {
                    Text(String(localized: "settings.appearance.size", defaultValue: "Size"))
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
                Toggle(String(localized: "settings.clipboard.enable", defaultValue: "Enable clipboard manager"), isOn: $store.clipboardEnabled)
                if store.clipboardEnabled {
                    ShortcutRecorderView(
                        label: String(localized: "settings.clipboard.show_clipboard", defaultValue: "Show clipboard"),
                        shortcut: $store.clipboardShortcut,
                        shortcutKeys: Binding(
                            get: { store.clipboardShortcutKeys },
                            set: { store.clipboardShortcutKeys = $0 }
                        )
                    )
                }
            }

            if store.clipboardEnabled {
                Section(String(localized: "settings.clipboard.behaviour", defaultValue: "Behaviour")) {
                    Picker(String(localized: "settings.clipboard.default_action", defaultValue: "Default action"), selection: $store.clipboardClickAction) {
                        Text(String(localized: "settings.clipboard.copy_to_clipboard", defaultValue: "Copy to clipboard")).tag("copy")
                        Text(String(localized: "settings.clipboard.paste_into_app", defaultValue: "Paste into active app")).tag("paste")
                    }
                }

                Section(String(localized: "settings.clipboard.history", defaultValue: "History")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(String(localized: "settings.clipboard.auto_delete", defaultValue: "Auto-delete entries older than"), selection: $store.clipboardAutoDelete) {
                            Text(String(localized: "settings.clipboard.never", defaultValue: "Never")).tag("never")
                            Text(String(localized: "settings.clipboard.1_hour", defaultValue: "1 hour")).tag("1h")
                            Text(String(localized: "settings.clipboard.12_hours", defaultValue: "12 hours")).tag("12h")
                            Text(String(localized: "settings.clipboard.1_day", defaultValue: "1 day")).tag("1d")
                            Text(String(localized: "settings.clipboard.7_days", defaultValue: "7 days")).tag("7d")
                            Text(String(localized: "settings.clipboard.14_days", defaultValue: "14 days")).tag("14d")
                            Text(String(localized: "settings.clipboard.30_days", defaultValue: "30 days")).tag("30d")
                        }
                        Text(String(localized: "settings.clipboard.max_entries", defaultValue: "Clipboard history stores up to 1,000 entries maximum."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "settings.clipboard.display", defaultValue: "Display")) {
                    Picker(String(localized: "settings.clipboard.view_mode", defaultValue: "View mode"), selection: $store.clipboardViewMode) {
                        Text(String(localized: "settings.clipboard.grid", defaultValue: "Grid")).tag("grid")
                        Text(String(localized: "settings.clipboard.panels", defaultValue: "Panels")).tag("panels")
                    }
                    HStack {
                        Text(String(localized: "settings.clipboard.preview_lines", defaultValue: "Preview lines"))
                        Spacer()
                        TextField("", value: $store.clipboardPreviewLines, format: .number)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Stepper("", value: $store.clipboardPreviewLines, in: 1...20)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    HStack {
                        Text(String(localized: "settings.clipboard.font_size", defaultValue: "Font size"))
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
