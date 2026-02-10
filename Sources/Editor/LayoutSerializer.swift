import Cocoa
import Bonsplit

enum LayoutSerializer {

    @MainActor
    static func captureLayout(controller: BonsplitController, tabIDMap: [UUID: TabID], clipboardTabID: TabID?) -> LayoutNode? {
        let tree = controller.treeSnapshot()
        let bonsplitToStore = buildExternalIDToStoreIDMap(tabIDMap: tabIDMap)
        let clipExternalID = clipboardTabID.flatMap { tabID -> String? in
            guard let data = try? JSONEncoder().encode(tabID),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
            return dict["id"]
        }
        return convertNode(tree, mapping: bonsplitToStore, clipboardExternalID: clipExternalID)
    }

    @MainActor
    static func findClipboardPane(in layout: LayoutNode?, controller: BonsplitController) -> PaneID? {
        guard let layout else { return nil }
        let paneIndex = clipboardPaneIndex(in: layout, currentIndex: 0)?.index
        guard let idx = paneIndex else { return nil }
        let panes = controller.allPaneIds
        return idx < panes.count ? panes[idx] : nil
    }

    private static func buildExternalIDToStoreIDMap(tabIDMap: [UUID: TabID]) -> [String: UUID] {
        var map: [String: UUID] = [:]
        for (tabStoreID, bonsplitTabID) in tabIDMap {
            if let data = try? JSONEncoder().encode(bonsplitTabID),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let uuidString = dict["id"] {
                map[uuidString] = tabStoreID
            }
        }
        return map
    }

    private static func convertNode(_ node: ExternalTreeNode, mapping: [String: UUID], clipboardExternalID: String?) -> LayoutNode? {
        switch node {
        case .pane(let paneNode):
            let tabIDs = paneNode.tabs.compactMap { mapping[$0.id] }
            let hasClipboard = clipboardExternalID.map { clipID in
                paneNode.tabs.contains { $0.id == clipID }
            } ?? false
            guard !tabIDs.isEmpty || hasClipboard else { return nil }
            let selectedID: UUID? = paneNode.selectedTabId.flatMap { mapping[$0] }
            return .pane(PaneNodeData(tabIDs: tabIDs, selectedTabID: selectedID, hasClipboard: hasClipboard))

        case .split(let splitNode):
            guard let first = convertNode(splitNode.first, mapping: mapping, clipboardExternalID: clipboardExternalID),
                  let second = convertNode(splitNode.second, mapping: mapping, clipboardExternalID: clipboardExternalID) else {
                let first = convertNode(splitNode.first, mapping: mapping, clipboardExternalID: clipboardExternalID)
                let second = convertNode(splitNode.second, mapping: mapping, clipboardExternalID: clipboardExternalID)
                return first ?? second
            }
            return .split(SplitNodeData(
                orientation: splitNode.orientation,
                dividerPosition: splitNode.dividerPosition,
                first: first,
                second: second
            ))
        }
    }

    private static func clipboardPaneIndex(in node: LayoutNode, currentIndex: Int) -> (index: Int, nextIndex: Int)? {
        switch node {
        case .pane(let data):
            if data.hasClipboard {
                return (index: currentIndex, nextIndex: currentIndex + 1)
            }
            return nil
        case .split(let data):
            if let found = clipboardPaneIndex(in: data.first, currentIndex: currentIndex) {
                return found
            }
            let firstCount = paneCount(in: data.first)
            return clipboardPaneIndex(in: data.second, currentIndex: currentIndex + firstCount)
        }
    }

    private static func paneCount(in node: LayoutNode) -> Int {
        switch node {
        case .pane: return 1
        case .split(let data): return paneCount(in: data.first) + paneCount(in: data.second)
        }
    }
}
