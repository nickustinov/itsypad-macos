import Cocoa
import SwiftUI

struct ClipboardTabView: NSViewRepresentable {
    let theme: EditorTheme
    var isSelected: Bool = false

    func makeNSView(context: Context) -> ClipboardContentView {
        let view = ClipboardContentView(frame: .zero)
        view.themeBackground = theme.background
        view.isDark = theme.isDark
        view.reloadEntries()
        return view
    }

    func updateNSView(_ view: ClipboardContentView, context: Context) {
        view.themeBackground = theme.background
        view.isDark = theme.isDark
        if isSelected {
            view.focusSearchField()
        }
    }
}
