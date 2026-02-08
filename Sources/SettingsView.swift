import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case editor
    case appearance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .editor: return "Editor"
        case .appearance: return "Appearance"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .editor: return "square.and.pencil"
        case .appearance: return "paintbrush"
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

    var body: some View {
        Form {
            Section("Itsypad") {
                Toggle("Open at login", isOn: $store.launchAtLogin)
                ShortcutRecorderView(
                    label: "Show Itsypad",
                    shortcut: $store.shortcut,
                    shortcutKeys: Binding(
                        get: { store.shortcutKeys },
                        set: { store.shortcutKeys = $0 }
                    )
                )
                Toggle("Always show in dock", isOn: $store.showInDock)
            }

            Section("Clipboard") {
                Toggle("Enable clipboard history", isOn: $store.clipboardEnabled)
                if store.clipboardEnabled {
                    ShortcutRecorderView(
                        label: "Show clipboard",
                        shortcut: $store.clipboardShortcut,
                        shortcutKeys: Binding(
                            get: { store.clipboardShortcutKeys },
                            set: { store.clipboardShortcutKeys = $0 }
                        )
                    )
                    Stepper("Max entries: \(store.clipboardMaxEntries)", value: $store.clipboardMaxEntries, in: 50...1000, step: 50)
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
}

struct EditorSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Word wrap", isOn: $store.wordWrap)
                Toggle("Show line numbers", isOn: $store.showLineNumbers)
                Toggle("Highlight current line", isOn: $store.highlightCurrentLine)
            }

            Section("Indentation") {
                Toggle("Indent using spaces", isOn: $store.indentUsingSpaces)
                Picker("Tab width", selection: $store.tabWidth) {
                    ForEach(1...8, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
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
                }
            }
        }
        .formStyle(.grouped)
    }
}

