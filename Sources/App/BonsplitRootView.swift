import SwiftUI
import Bonsplit

struct BonsplitRootView: View {
    let coordinator: EditorCoordinator

    var body: some View {
        BonsplitView(controller: coordinator.controller) { tab, paneId in
            let isSelected = coordinator.controller.selectedTab(inPane: paneId)?.id == tab.id

            Group {
                if tab.id == coordinator.clipboardTabID {
                    ClipboardTabView(theme: clipboardTheme, isSelected: isSelected)
                } else if let state = coordinator.editorState(for: tab.id) {
                    if coordinator.isPreviewActive(for: tab.id),
                       let html = coordinator.previewHTML(for: tab.id) {
                        HSplitView {
                            EditorContentView(editorState: state, isSelected: isSelected)
                                .frame(minWidth: 200)
                            MarkdownPreviewView(
                                html: html,
                                baseURL: coordinator.previewBaseURL(for: tab.id),
                                theme: coordinator.cssTheme
                            )
                            .frame(minWidth: 200)
                        }
                    } else {
                        EditorContentView(editorState: state, isSelected: isSelected)
                    }
                } else {
                    Text(String(localized: "editor.tab_not_found", defaultValue: "Tab not found"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: isSelected) { _, newValue in
                if newValue {
                    coordinator.postMarkdownState(for: tab.id)
                }
            }
        } emptyPane: { paneId in
            Text(String(localized: "editor.no_open_tabs", defaultValue: "No open tabs"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var clipboardTheme: EditorTheme {
        coordinator.cssTheme
    }
}
