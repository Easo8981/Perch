import SwiftUI

/// SwiftUI list of stored items, hosted in the panel via `NSHostingView`.
struct ShelfContentView: View {
    @ObservedObject var store: ItemStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.items) { item in
                    ItemRowView(item: item)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
