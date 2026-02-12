import SwiftUI
import AppKit

/// Recursively renders a split node (pane or split)
struct SplitNodeView<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller

    let node: SplitNode
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?

    var body: some View {
        switch node {
        case .pane(let paneState):
            SinglePaneWrapper(
                pane: paneState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )

        case .split(let splitState):
            SplitContainerView(
                splitState: splitState,
                controller: controller,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                onGeometryChange: onGeometryChange
            )
        }
    }
}

/// Wrapper that uses NSHostingController for proper AppKit layout constraints
struct SinglePaneWrapper<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Environment(SplitViewController.self) private var controller

    let pane: PaneState
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    func makeNSView(context: Context) -> NSView {
        let paneView = PaneContainerView(
            pane: pane,
            controller: controller,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        let hostingView = CursorPassthroughHostingView(rootView: paneView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let containerView = NSView()
        containerView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        context.coordinator.hostingView = hostingView

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let paneView = PaneContainerView(
            pane: pane,
            controller: controller,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        context.coordinator.hostingView?.rootView = paneView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingView: CursorPassthroughHostingView<PaneContainerView<Content, EmptyContent>>?
    }
}
