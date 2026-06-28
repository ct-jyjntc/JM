import SwiftUI

struct ComicGridView: View {
    let items: [FeedComic]
    let hideCovers: Bool
    let open: (String) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 220), spacing: AppTheme.gridSpacing)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.gridSpacing) {
            ForEach(items) { item in
                Button {
                    open(item.id)
                } label: {
                    ComicCardView(comic: item, hideCover: hideCovers)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
