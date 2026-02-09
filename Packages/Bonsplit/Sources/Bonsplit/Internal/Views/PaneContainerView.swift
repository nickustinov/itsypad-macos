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
            // Tab bar
            TabBarView(
                pane: pane,
                isFocused: isFocused,
                showSplitButtons: showSplitButtons
            )

            // Content area with drop zones
            contentAreaWithDropZones
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Content Area with Drop Zones

    @ViewBuilder
    private var contentAreaWithDropZones: some View {
        GeometryReader { geometry in
            let size = geometry.size

            contentArea
                .frame(width: size.width, height: size.height)
        }
        .clipped()
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
                // macOS-like behavior: keep all tab views in hierarchy.
                // We use NSView.isHidden instead of SwiftUI opacity(0)
                // because opacity(0) leaves NSTextView cursor rects active,
                // leaking I-beam cursors into non-editor tabs.
                ZStack {
                    ForEach(pane.tabs) { tab in
                        let isVisible = tab.id == pane.selectedTabId
                        HiddenWhenInactive(isVisible: isVisible) {
                            contentBuilder(tab, pane.id)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .allowsHitTesting(isVisible)
                    }
                }
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

// MARK: - Hidden-when-inactive wrapper

/// Wraps SwiftUI content in an NSView and uses `isHidden` to hide inactive tabs.
/// Unlike SwiftUI's `opacity(0)`, setting `isHidden = true` on the NSView prevents
/// AppKit from calling `resetCursorRects` on child views, which stops hidden
/// NSTextViews from leaking I-beam cursor rects into other tabs.
private struct HiddenWhenInactive<Content: View>: NSViewRepresentable {
    var isVisible: Bool
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSView {
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.isHidden = !isVisible
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.isHidden = !isVisible
        if let host = container.subviews.first as? NSHostingView<Content> {
            host.rootView = content
        }
    }
}
