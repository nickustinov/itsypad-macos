import Cocoa
import SwiftUI

struct EditorContentView: NSViewRepresentable {
    let editorState: EditorState
    var isSelected: Bool

    func makeNSView(context: Context) -> NSView {
        let host = EditorContentHostView(editorState: editorState)
        return host
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Apply theme
        let theme = editorState.highlightCoordinator.theme
        guard let host = container as? EditorContentHostView else { return }
        host.applyTheme(theme)
        host.updateWordCount()
        host.updateGutterVisibility()

        // Claim first responder when this tab becomes selected.
        // Always defer to next run loop – Bonsplit switches tabs by hiding/unhiding
        // hosting views, and the text view may not accept first responder until
        // AppKit finishes processing the visibility change.
        if isSelected {
            let textView = editorState.textView
            DispatchQueue.main.async {
                if let window = textView.window, window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
            }
        }
    }
}

private final class EditorContentHostView: NSView {
    private let textView: EditorTextView
    private let scrollView: NSScrollView
    private let gutter: LineNumberGutterView
    private var gutterWidthConstraint: NSLayoutConstraint!
    let statusLabel: NSTextField
    private var textDidChangeObserver: NSObjectProtocol?

    init(editorState: EditorState) {
        self.textView = editorState.textView
        self.scrollView = editorState.scrollView
        self.gutter = editorState.gutterView

        let label = NSTextField(labelWithString: "Words: 0")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.isEditable = false
        label.isSelectable = false
        label.backgroundColor = .clear
        statusLabel = label

        let initialLineCount = textView.string.components(separatedBy: "\n").count
        let gutterWidth = SettingsStore.shared.showLineNumbers
            ? LineNumberGutterView.calculateWidth(lineCount: initialLineCount, font: gutter.lineFont)
            : 1
        let gutterWidthConstraint = gutter.widthAnchor.constraint(
            equalToConstant: gutterWidth
        )
        gutterWidthConstraint.identifier = "gutterWidth"
        gutter.showLineNumbers = SettingsStore.shared.showLineNumbers

        super.init(frame: .zero)
        self.gutterWidthConstraint = gutterWidthConstraint
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        gutter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutter)
        addSubview(scrollView)
        addSubview(statusLabel)

        gutter.attach(to: scrollView, textView: textView)

        NSLayoutConstraint.activate([
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])

        updateGutterVisibility()

        textDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.updateWordCount()
        }

        updateWordCount()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(_ theme: EditorTheme) {
        if let window {
            window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        }
    }

    func updateGutterVisibility() {
        let showGutter = SettingsStore.shared.showLineNumbers
        gutterWidthConstraint.constant = showGutter ? gutterWidth(for: gutter, textView: textView) : 1
        gutter.showLineNumbers = showGutter
    }

    private func gutterWidth(for gutter: LineNumberGutterView, textView: EditorTextView) -> CGFloat {
        let lineCount = textView.string.components(separatedBy: "\n").count
        return LineNumberGutterView.calculateWidth(lineCount: lineCount, font: gutter.lineFont)
    }

    deinit {
        if let observer = textDidChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func updateWordCount() {
        let text = textView.string
        let words = WordCountHelpers.wordCount(in: text)
        statusLabel.stringValue = "Words: \(words)"
    }
}
