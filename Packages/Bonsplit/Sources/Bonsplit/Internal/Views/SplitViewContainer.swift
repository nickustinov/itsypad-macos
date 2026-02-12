import SwiftUI

/// Main container view that renders the entire split tree (internal implementation)
struct SplitViewContainer<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller
    @Environment(BonsplitController.self) private var bonsplitController

    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            RootNodeContainer(
                node: controller.rootNode,
                controller: controller,
                bonsplitController: bonsplitController,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                onGeometryChange: onGeometryChange
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .onChange(of: geometry.size) { _, newSize in
                updateContainerFrame(geometry: geometry)
            }
            .onAppear {
                updateContainerFrame(geometry: geometry)
            }
        }
    }

    private func updateContainerFrame(geometry: GeometryProxy) {
        let frame = geometry.frame(in: .global)
        controller.containerFrame = frame
        onGeometryChange?(false)
    }
}

// MARK: - Persistent root node container

/// Renders the root split node inside a persistent hosting view.
///
/// `SplitNodeView.body` switches between `SinglePaneWrapper` and
/// `SplitContainerView` -- two different `NSViewRepresentable` types.
/// On macOS 14-15 this structural view-type switch causes the surviving
/// pane's content to disappear because AppKit views fail to render after
/// the full teardown/recreate cycle.
///
/// By hosting `SplitNodeView` inside a stable `CursorPassthroughHostingView`
/// that is never removed from the window, the branch switch happens within
/// a hosting view that stays connected -- the same pattern
/// `SplitContainerView` already uses for its child nodes.
private struct RootNodeContainer<Content: View, EmptyContent: View>: NSViewRepresentable {
    let node: SplitNode
    let controller: SplitViewController
    let bonsplitController: BonsplitController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool
    var contentViewLifecycle: ContentViewLifecycle
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let hosting = CursorPassthroughHostingView(rootView: AnyView(EmptyView()))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.hostingView = hosting
        updateHosting(context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateHosting(context.coordinator)
    }

    private func updateHosting(_ coordinator: Coordinator) {
        coordinator.hostingView?.rootView = AnyView(
            SplitNodeView(
                node: node,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                onGeometryChange: onGeometryChange
            )
            .environment(controller)
            .environment(bonsplitController)
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingView: CursorPassthroughHostingView<AnyView>?
    }
}
