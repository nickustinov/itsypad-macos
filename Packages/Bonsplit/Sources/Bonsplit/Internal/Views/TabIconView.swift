import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Renders a tab icon from either an SF Symbol name or a named image resource.
struct TabIconView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            Image(systemName: name)
                .font(.system(size: size))
        } else if let nsImage = NSImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size + 2, height: size + 2)
        }
    }
}
