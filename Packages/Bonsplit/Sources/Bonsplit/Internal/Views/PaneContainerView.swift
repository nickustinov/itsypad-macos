import SwiftUI

/// Container for a single pane with its tab bar and content area
struct PaneContainerView<Content: View, EmptyContent: View>: View {
    @Bindable var pane: PaneState
    let controller: SplitViewController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — wrapped in ArrowCursorOverlay to explicitly set arrow cursor,
            // since CursorPassthroughHostingView at the parent level neutralizes cursor handling.
            TabBarView(
                pane: pane,
                isFocused: isFocused,
                showSplitButtons: showSplitButtons
            )
            .overlay { ArrowCursorOverlay().allowsHitTesting(false) }

            // Content area
            contentArea
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if pane.tabs.isEmpty {
            emptyPaneView
        } else {
            switch contentViewLifecycle {
            case .recreateOnSwitch:
                // Original behavior: only render selected tab
                if let selectedTab = pane.selectedTab {
                    contentBuilder(selectedTab, pane.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

            case .keepAllAlive:
                // Keep all tab views alive using a flat AppKit container.
                // Each tab gets its own CursorPassthroughHostingView managed at
                // the AppKit level. isHidden prevents cursor rect leaking.
                // This avoids nested SwiftUI hosting views which cause
                // AttributeGraph cycles and blank content.
                TabContentContainer(
                    tabs: pane.tabs,
                    selectedTabId: pane.selectedTabId,
                    paneId: pane.id,
                    pane: pane,
                    contentBuilder: contentBuilder
                )
            }
        }
    }

    // MARK: - Empty Pane View

    @ViewBuilder
    private var emptyPaneView: some View {
        emptyPaneBuilder(pane.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Arrow cursor overlay

/// Transparent NSView overlay that sets an arrow cursor rect over its entire bounds.
/// Used on the tab bar to restore the arrow cursor in areas where
/// CursorPassthroughHostingView has neutralized the hosting view's default behavior.
private struct ArrowCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> ArrowCursorNSView {
        ArrowCursorNSView()
    }

    func updateNSView(_ nsView: ArrowCursorNSView, context: Context) {}
}

private class ArrowCursorNSView: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

// MARK: - Tab content container

/// Manages all tab content views at the AppKit level using a flat container.
/// Each tab gets its own CursorPassthroughHostingView as a direct subview,
/// with isHidden controlling visibility. This avoids the nested hosting view
/// pattern (NSViewRepresentable -> NSHostingView -> NSViewRepresentable)
/// that causes AttributeGraph cycles.
///
/// Hosting views are cached in PaneState.hostingViewCache so they survive
/// view lifecycle transitions (e.g. pane collapse). When a split collapses,
/// the old TabContentContainer is destroyed but the cached hosting views are
/// reused by the new TabContentContainer, avoiding AppKit view reparenting
/// that fails to render on macOS 14-15.
private struct TabContentContainer<Content: View>: NSViewRepresentable {
    let tabs: [TabItem]
    let selectedTabId: UUID?
    let paneId: PaneID
    let pane: PaneState
    let contentBuilder: (TabItem, PaneID) -> Content

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        for tab in tabs {
            if let cached = pane.hostingViewCache[tab.id] {
                // Reuse hosting view preserved across pane collapse
                cached.removeFromSuperview()
                cached.isHidden = tab.id != selectedTabId
                cached.rootView = AnyView(
                    contentBuilder(tab, paneId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
                container.addSubview(cached)
                NSLayoutConstraint.activate([
                    cached.topAnchor.constraint(equalTo: container.topAnchor),
                    cached.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    cached.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    cached.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
                context.coordinator.hostingViews[tab.id] = cached
            } else {
                addHostingView(for: tab, to: container, coordinator: context.coordinator)
            }
        }
        // Sync cache with current hosting views
        pane.hostingViewCache = context.coordinator.hostingViews
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let coordinator = context.coordinator
        let currentTabIds = Set(tabs.map(\.id))

        // Remove hosting views for tabs that no longer exist
        for (tabId, hosting) in coordinator.hostingViews where !currentTabIds.contains(tabId) {
            hosting.removeFromSuperview()
            coordinator.hostingViews.removeValue(forKey: tabId)
            pane.hostingViewCache.removeValue(forKey: tabId)
        }

        // Add or update hosting views
        for tab in tabs {
            if let hosting = coordinator.hostingViews[tab.id] {
                // Update visibility
                hosting.isHidden = tab.id != selectedTabId
                // Update content
                hosting.rootView = AnyView(
                    contentBuilder(tab, paneId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                )
            } else {
                // New tab -- add hosting view
                addHostingView(for: tab, to: container, coordinator: coordinator)
            }
        }

        // Keep cache in sync
        pane.hostingViewCache = coordinator.hostingViews
    }

    private func addHostingView(for tab: TabItem, to container: NSView, coordinator: Coordinator) {
        let content = AnyView(
            contentBuilder(tab, paneId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let hosting = CursorPassthroughHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.isHidden = tab.id != selectedTabId
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        coordinator.hostingViews[tab.id] = hosting
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingViews: [UUID: CursorPassthroughHostingView<AnyView>] = [:]
    }
}
