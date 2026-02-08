import Cocoa
import SwiftUI

struct EditorContentView: NSViewRepresentable {
    let editorState: EditorState
    var isSelected: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let scrollView = editorState.scrollView
        let textView = editorState.textView
        let gutter = editorState.gutterView

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        gutter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(gutter)
        container.addSubview(scrollView)

        // Attach gutter to the scroll view and text view
        gutter.attach(to: scrollView, textView: textView)

        let settings = SettingsStore.shared
        let showGutter = settings.showLineNumbers
        let gutterWidth = calculateGutterWidth(for: editorState)

        let gutterWidthConstraint = gutter.widthAnchor.constraint(equalToConstant: showGutter ? gutterWidth : 0)
        gutterWidthConstraint.identifier = "gutterWidth"

        NSLayoutConstraint.activate([
            gutter.topAnchor.constraint(equalTo: container.topAnchor),
            gutter.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            gutter.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            gutterWidthConstraint,

            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        gutter.isHidden = !showGutter

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let settings = SettingsStore.shared
        let showGutter = settings.showLineNumbers
        let gutter = editorState.gutterView

        gutter.isHidden = !showGutter

        if let gutterWidthConstraint = container.constraints.first(where: { $0.identifier == "gutterWidth" }) {
            gutterWidthConstraint.constant = showGutter ? calculateGutterWidth(for: editorState) : 0
        }

        // Apply theme
        let theme = editorState.highlightCoordinator.theme
        container.window?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        // Claim first responder when this tab becomes selected
        if isSelected {
            let textView = editorState.textView
            if let window = textView.window, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }
    }

    private func calculateGutterWidth(for state: EditorState) -> CGFloat {
        let lineCount = state.textView.string.components(separatedBy: "\n").count
        let digits = max(3, "\(lineCount)".count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: state.gutterView.lineFont]).width
        return CGFloat(digits) * digitWidth + 16
    }
}
