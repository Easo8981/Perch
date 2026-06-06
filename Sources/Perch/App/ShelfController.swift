import AppKit

/// `@MainActor` coordinator that wires the store, windows, and the three pipelines.
@MainActor
final class ShelfController: ShelfDropHandling, EdgeStripDelegate {
    private let panel: ShelfPanel

    init() throws {
        panel = ShelfPanel(contentRect: Self.initialPanelFrame())
    }

    /// Build the windows, load the store, and start observing drags.
    func start() {
        panel.orderFrontRegardless()
    }

    // MARK: ShelfDropHandling

    func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
        fatalError("unimplemented")
    }

    // MARK: EdgeStripDelegate

    func edgeStripDidReceiveDrag(_ strip: EdgeStripWindow) {
        fatalError("unimplemented")
    }

    private static func initialPanelFrame() -> NSRect {
        let fallbackFrame = NSRect(x: 0, y: 0, width: 320, height: 640)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? fallbackFrame
        let width = min(CGFloat(320), visibleFrame.width)

        return NSRect(
            x: visibleFrame.maxX - width,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        )
    }
}
