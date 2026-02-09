import SwiftUI

/// NSHostingView subclass that doesn't interfere with child AppKit views' cursors.
///
/// NSHostingView installs tracking areas with `.cursorUpdate` that set the arrow cursor.
/// These tracking areas take priority over cursor rects (e.g. NSTextView's I-beam),
/// causing the cursor to flash to arrow during scroll and click events.
///
/// This subclass neutralizes all three cursor mechanisms:
/// - `resetCursorRects`: no cursor rects added
/// - `cursorUpdate`: no cursor set via tracking area callbacks
/// - `updateTrackingAreas`: removes `.cursorUpdate` tracking areas added by super
class CursorPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        // Don't add any cursor rects
    }

    override func cursorUpdate(with event: NSEvent) {
        // Don't set any cursor — let child AppKit views handle it
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove any cursor-update tracking areas that NSHostingView added
        for area in trackingAreas where area.options.contains(.cursorUpdate) {
            removeTrackingArea(area)
        }
    }
}
