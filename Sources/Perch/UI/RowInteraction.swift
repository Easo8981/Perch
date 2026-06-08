import Combine
import CoreGraphics
import Foundation

/// Which row the pointer is currently over. Updated by `ShelfHostView`'s AppKit
/// mouse-tracking (the SwiftUI content never receives mouse events, since the host
/// view intercepts hit-testing) and observed by the SwiftUI rows to show the hover
/// highlight + delete button.
@MainActor
final class RowInteractionState: ObservableObject {
    @Published var hoveredItemID: UUID?
}

/// Delete-button layout constants shared between the SwiftUI rendering (`ItemRowView`)
/// and the AppKit hit-testing (`ShelfHostView`) so the drawn button and its clickable
/// rect line up. Row height/spacing/padding live on `ShelfTheme`.
enum RowMetrics {
    /// Delete button diameter.
    static let deleteDiameter: CGFloat = 20
    /// Trailing inset of the delete button from the row's right edge.
    static let deleteTrailingInset: CGFloat = 7
}
