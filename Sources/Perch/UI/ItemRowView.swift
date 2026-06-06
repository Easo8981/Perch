import SwiftUI

/// SwiftUI view for a single stored item (icon + title).
struct ItemRowView: View {
    let item: StoredItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: item.iconImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)

            Text(item.metadata.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}
