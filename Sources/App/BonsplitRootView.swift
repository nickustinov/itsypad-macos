import SwiftUI
import Bonsplit

struct BonsplitRootView: View {
    let coordinator: EditorCoordinator

    var body: some View {
        BonsplitView(controller: coordinator.controller) { tab, paneId in
            if tab.id == coordinator.clipboardTabID {
                let isSelected = coordinator.controller.selectedTab(inPane: paneId)?.id == tab.id
                ClipboardTabView(theme: clipboardTheme, isSelected: isSelected)
            } else if let state = coordinator.editorState(for: tab.id) {
                let isSelected = coordinator.controller.selectedTab(inPane: paneId)?.id == tab.id
                EditorContentView(editorState: state, isSelected: isSelected)
            } else {
                Text("Tab not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } emptyPane: { paneId in
            Text("No open tabs")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var clipboardTheme: EditorTheme {
        coordinator.cssTheme
    }
}
