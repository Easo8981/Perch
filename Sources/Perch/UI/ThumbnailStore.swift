import AppKit
import QuickLookThumbnailing

/// Generates and caches real Quick Look content thumbnails (image/PDF/document previews)
/// for stored items, off the main thread. `thumbnail(for:)` returns a cached preview if
/// one exists, otherwise kicks off generation and returns nil (the row shows the
/// file-type icon until the preview arrives). Only genuine *content* thumbnails are
/// cached — files Quick Look can't preview fall back to the icon permanently.
@MainActor
final class ThumbnailStore: ObservableObject {
    /// Republished whenever a new thumbnail lands, so observing rows refresh.
    @Published private var cache: [UUID: NSImage] = [:]
    private var inFlight: Set<UUID> = []

    /// Rendered display size; the generator output is sized for this at screen scale.
    private static let pointSize: CGFloat = 40

    func thumbnail(for item: StoredItem) -> NSImage? {
        if let cached = cache[item.id] { return cached }
        requestIfNeeded(for: item)
        return nil
    }

    private func requestIfNeeded(for item: StoredItem) {
        guard cache[item.id] == nil, !inFlight.contains(item.id) else { return }
        guard let url = item.backingFileURLs().first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { return }

        inFlight.insert(item.id)
        let id = item.id
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: Self.pointSize, height: Self.pointSize),
            scale: scale,
            representationTypes: .thumbnail
        )

        Task { [weak self] in
            let representation = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            guard let self else { return }
            self.inFlight.remove(id)
            if let representation {
                self.cache[id] = representation.nsImage
            }
        }
    }
}
