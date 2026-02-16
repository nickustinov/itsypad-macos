import Cocoa
import Bonsplit

struct SessionRestoreResult {
    var tabIDMap: [UUID: TabID]
    var reverseMap: [TabID: UUID]
    var editorStates: [TabID: EditorState]
}

struct SessionRestorer {
    let controller: BonsplitController
    let tabStore: TabStore
    let createEditorState: (TabData) -> EditorState

    @MainActor
    func restore() -> SessionRestoreResult {
        let tabsByID = Dictionary(tabStore.tabs.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })

        var result: SessionRestoreResult
        if let layout = tabStore.savedLayout {
            result = restoreWithLayout(layout, tabsByID: tabsByID)
        } else {
            result = restoreWithoutLayout(tabsByID: tabsByID)
        }

        return result
    }

    @MainActor
    private func restoreWithoutLayout(tabsByID: [UUID: TabData]) -> SessionRestoreResult {
        var tabIDMap: [UUID: TabID] = [:]
        var reverseMap: [TabID: UUID] = [:]
        var editorStates: [TabID: EditorState] = [:]

        for tab in tabStore.tabs {
            if let bonsplitTabID = controller.createTab(
                title: tab.name,
                icon: nil,
                isDirty: tab.isDirty,
                isPinned: tab.isPinned
            ) {
                tabIDMap[tab.id] = bonsplitTabID
                reverseMap[bonsplitTabID] = tab.id
                editorStates[bonsplitTabID] = createEditorState(tab)
            }
        }

        return SessionRestoreResult(tabIDMap: tabIDMap, reverseMap: reverseMap, editorStates: editorStates)
    }

    @MainActor
    private func restoreWithLayout(_ layout: LayoutNode, tabsByID: [UUID: TabData]) -> SessionRestoreResult {
        var tabIDMap: [UUID: TabID] = [:]
        var reverseMap: [TabID: UUID] = [:]
        var editorStates: [TabID: EditorState] = [:]

        guard let rootPane = controller.focusedPaneId else {
            return SessionRestoreResult(tabIDMap: tabIDMap, reverseMap: reverseMap, editorStates: editorStates)
        }

        var paneSelections: [(PaneID, UUID)] = []

        restoreNode(
            layout, inPane: rootPane, tabsByID: tabsByID,
            paneSelections: &paneSelections,
            tabIDMap: &tabIDMap, reverseMap: &reverseMap, editorStates: &editorStates
        )

        // Create any tabs that weren't in the layout (safety net)
        let restoredIDs = Set(tabIDMap.keys)
        for tab in tabStore.tabs where !restoredIDs.contains(tab.id) {
            if let bonsplitTabID = controller.createTab(
                title: tab.name,
                icon: nil,
                isDirty: tab.isDirty,
                isPinned: tab.isPinned
            ) {
                tabIDMap[tab.id] = bonsplitTabID
                reverseMap[bonsplitTabID] = tab.id
                editorStates[bonsplitTabID] = createEditorState(tab)
            }
        }

        // Restore per-pane selections
        for (paneID, tabStoreID) in paneSelections {
            if let bonsplitID = tabIDMap[tabStoreID] {
                controller.selectTab(bonsplitID)
            }
            _ = paneID
        }

        // Restore divider positions after layout pass
        let savedLayout = layout
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let newTree = self.controller.treeSnapshot()
                self.restoreDividerPositions(saved: savedLayout, current: newTree)
            }
        }

        return SessionRestoreResult(tabIDMap: tabIDMap, reverseMap: reverseMap, editorStates: editorStates)
    }

    @MainActor
    @discardableResult
    private func restoreNode(
        _ node: LayoutNode,
        inPane pane: PaneID,
        tabsByID: [UUID: TabData],
        paneSelections: inout [(PaneID, UUID)],
        tabIDMap: inout [UUID: TabID],
        reverseMap: inout [TabID: UUID],
        editorStates: inout [TabID: EditorState]
    ) -> PaneID {
        switch node {
        case .pane(let data):
            for tabID in data.tabIDs {
                guard let tab = tabsByID[tabID] else { continue }
                if let bonsplitTabID = controller.createTab(
                    title: tab.name,
                    icon: nil,
                    isDirty: tab.isDirty,
                    isPinned: tab.isPinned,
                    inPane: pane
                ) {
                    tabIDMap[tab.id] = bonsplitTabID
                    reverseMap[bonsplitTabID] = tab.id
                    editorStates[bonsplitTabID] = createEditorState(tab)
                }
            }
            if let selectedID = data.selectedTabID {
                paneSelections.append((pane, selectedID))
            }
            return pane

        case .split(let data):
            let orientation: SplitOrientation = data.orientation == "vertical" ? .vertical : .horizontal

            restoreNode(data.first, inPane: pane, tabsByID: tabsByID, paneSelections: &paneSelections,
                        tabIDMap: &tabIDMap, reverseMap: &reverseMap, editorStates: &editorStates)

            guard let newPane = controller.splitPane(pane, orientation: orientation) else {
                restoreNode(data.second, inPane: pane, tabsByID: tabsByID, paneSelections: &paneSelections,
                            tabIDMap: &tabIDMap, reverseMap: &reverseMap, editorStates: &editorStates)
                return pane
            }

            restoreNode(data.second, inPane: newPane, tabsByID: tabsByID, paneSelections: &paneSelections,
                        tabIDMap: &tabIDMap, reverseMap: &reverseMap, editorStates: &editorStates)

            return pane
        }
    }

    @MainActor
    private func restoreDividerPositions(saved: LayoutNode, current: ExternalTreeNode) {
        guard case .split(let savedSplit) = saved,
              case .split(let currentSplit) = current else { return }

        if let splitID = UUID(uuidString: currentSplit.id) {
            controller.setDividerPosition(CGFloat(savedSplit.dividerPosition), forSplit: splitID, fromExternal: true)
        }

        restoreDividerPositions(saved: savedSplit.first, current: currentSplit.first)
        restoreDividerPositions(saved: savedSplit.second, current: currentSplit.second)
    }
}
