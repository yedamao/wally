import AppKit
import WebKit

/// WKWebView that lets the user drag the window from the top chrome
/// (below the traffic lights), while clicks lower in the page still go
/// to the page. Needed when the window uses a transparent
/// fullSizeContentView title bar.
final class DraggableWebView: WKWebView {
    /// Height of the drag strip at the top of the view, in points.
    var dragRegionHeight: CGFloat = 52
    /// Trailing inset reserved for native toolbar buttons.
    var dragRegionTrailingInset: CGFloat = 140

    override func mouseDown(with event: NSEvent) {
        if shouldDrag(with: event), let window {
            window.performDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    private func shouldDrag(with event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        // AppKit y grows upward: the top strip is near bounds.maxY.
        guard point.y >= bounds.maxY - dragRegionHeight else { return false }
        guard point.x < bounds.maxX - dragRegionTrailingInset else { return false }
        // Leave the traffic-light area alone (system handles it).
        guard point.x > 78 else { return false }
        return true
    }
}
