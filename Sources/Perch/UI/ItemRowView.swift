import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI view for a single stored item (icon + title + kind). Pinned to exactly
/// `RowMetrics.height` so the window can size to its contents precisely. Hover state is
/// supplied by AppKit (`ShelfHostView`), since the host view intercepts mouse events;
/// the delete "✕" is drawn here but its click is handled in AppKit too.
struct ItemRowView: View {
    let item: StoredItem
    let theme: ShelfTheme
    let isHovered: Bool
    /// A real Quick Look content preview, if one has been generated; otherwise nil and
    /// we fall back to the file-type icon.
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(item.metadata.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: RowMetrics.height,
            maxHeight: RowMetrics.height,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
                .fill(isHovered ? theme.rowHoverFill : theme.rowFill)
        )
        .overlay(alignment: .trailing) { deleteButton }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: thumbnail != nil)
    }

    /// A real preview is shown as a small rounded "photo" tile; a generic file icon is
    /// shown at its natural shape.
    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                .transition(.opacity)
        } else {
            Image(nsImage: item.iconImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.5)
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if theme.showsDeleteButton && isHovered {
            ZStack {
                Circle().fill(.thinMaterial)
                Circle().stroke(.white.opacity(0.18), lineWidth: 0.5)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: RowMetrics.deleteDiameter, height: RowMetrics.deleteDiameter)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .padding(.trailing, RowMetrics.deleteTrailingInset)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }

    private var subtitle: String {
        if let name = item.metadata.backingFileNames.first,
           name.contains("."),
           let ext = name.split(separator: ".").last {
            return ext.uppercased()
        }
        if let type = item.metadata.primaryFileType,
           let contentType = UTType(type),
           let description = contentType.localizedDescription {
            return description.capitalized
        }
        return "Clipping"
    }
}
