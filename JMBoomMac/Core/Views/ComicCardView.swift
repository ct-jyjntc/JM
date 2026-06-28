import SwiftUI

struct ComicCardView: View {
    let comic: FeedComic
    let hideCover: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                RemoteCoverView(title: comic.title, imageURL: comic.image, hideCover: hideCover)

                Text("JM \(comic.id)")
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(comic.title)
                    .font(.headline)
                    .lineLimit(2)
                    .help(comic.title)

                Text(comic.author.isEmpty ? "N/A" : comic.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: AppTheme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .contentShape(.rect)
    }
}
