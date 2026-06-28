import SwiftUI

struct ComicDetailView: View {
    let comicId: String

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ComicDetailViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && viewModel.comic == nil {
                    LoadingStateView(title: "正在加载详情")
                } else if let error = viewModel.errorMessage {
                    ErrorStateView(title: "详情加载失败", message: error) {
                        Task { await viewModel.refresh(comicId: comicId, endpoint: settings.apiEndpoint) }
                    }
                } else if let comic = viewModel.comic {
                    ComicDetailContentView(comic: comic)
                } else {
                    EmptyStateView(title: "暂无详情", message: "当前作品没有返回可展示的详情。")
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("JM \(comicId)")
        .toolbar {
            Button("刷新", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh(comicId: comicId, endpoint: settings.apiEndpoint) }
            }
            .labelStyle(.iconOnly)
            .help("刷新")
        }
        .task(id: comicId) {
            await viewModel.load(comicId: comicId, endpoint: settings.apiEndpoint)
        }
    }
}

private struct ComicDetailContentView: View {
    let comic: ComicDetail

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(FavoriteStore.self) private var favorites

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ComicHeroView(comic: comic, hideCover: settings.hideCovers, isFavorite: favorites.contains(comic.id)) {
                favorites.toggle(comic)
            }

            HStack(alignment: .top, spacing: 24) {
                ChaptersView(comic: comic) { chapter, chapterTitle, chapters in
                    router.openReader(
                        ReaderRoute(
                            chapterId: chapter.id,
                            albumId: comic.seriesId.isEmpty ? comic.id : comic.seriesId,
                            title: comic.title,
                            author: comic.author.joined(separator: ", "),
                            coverURL: comic.image,
                            chapterTitle: chapterTitle,
                            initialPageIndex: 0,
                            chapters: chapters
                        )
                    )
                }

                RelatedListView(items: comic.relatedList) { id in
                    router.openComic(id)
                }
                .frame(width: AppTheme.detailColumnWidth)
            }
        }
    }
}

private struct ComicHeroView: View {
    let comic: ComicDetail
    let hideCover: Bool
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            RemoteCoverView(title: comic.title, imageURL: comic.image, hideCover: hideCover)
                .frame(width: 220)
                .clipShape(.rect(cornerRadius: AppTheme.cardCornerRadius))

            VStack(alignment: .leading, spacing: 12) {
                Text(comic.title)
                    .font(.largeTitle)
                    .bold()
                    .fixedSize(horizontal: false, vertical: true)

                if !comic.author.isEmpty {
                    Label(comic.author.joined(separator: ", "), systemImage: "person")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Label("\(comic.totalViews)", systemImage: "eye")
                    Label("\(comic.likes)", systemImage: "heart")
                    Label("\(comic.commentTotal)", systemImage: "bubble")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "heart.fill" : "heart", action: toggleFavorite)

                if !comic.description.isEmpty {
                    Text(comic.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TagCloudView(tags: comic.tags + comic.actors + comic.works)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TagCloudView: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(Set(tags)).sorted(), id: \.self) { tag in
                Text(tag)
                    .font(.subheadline)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

private struct ChaptersView: View {
    let comic: ComicDetail
    let open: (ComicChapter, String, [ReaderChapterReference]) -> Void

    private var indexedChapters: [IndexedChapter] {
        sortedChapters(comic.series).enumerated().map { index, chapter in
            IndexedChapter(index: index, chapter: chapter)
        }
    }

    private var readerChapters: [ReaderChapterReference] {
        Array(indexedChapters.reversed()).enumerated().map { index, indexed in
            ReaderChapterReference(id: indexed.chapter.id, title: formatChapterTitle(indexed.chapter, index: index))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("章节")
                .font(.title2)
                .bold()

            if indexedChapters.isEmpty {
                EmptyStateView(title: "暂无章节", message: "当前作品没有可阅读章节。")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(indexedChapters, id: \.chapter.id) { indexed in
                        let chapterTitle = readerChapters.first { $0.id == indexed.chapter.id }?.title ?? formatChapterTitle(indexed.chapter, index: indexed.index)

                        Button {
                            open(indexed.chapter, chapterTitle, readerChapters)
                        } label: {
                            Label(chapterTitle, systemImage: "book")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IndexedChapter {
    let index: Int
    let chapter: ComicChapter
}

private func sortedChapters(_ chapters: [ComicChapter]) -> [ComicChapter] {
    chapters.sorted { left, right in
        guard let leftSort = Int(left.sort), let rightSort = Int(right.sort) else {
            return false
        }
        return leftSort > rightSort
    }
}

private func formatChapterTitle(_ chapter: ComicChapter, index: Int) -> String {
    let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !title.isEmpty {
        return title
    }
    return chapter.sort.isEmpty ? "章节 \(index + 1)" : "第 \(chapter.sort) 章"
}

private struct RelatedListView: View {
    let items: [RelatedComic]
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("相关作品")
                .font(.title3)
                .bold()

            if items.isEmpty {
                Text("暂无相关作品")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        open(item.id)
                    } label: {
                        HStack(spacing: 10) {
                            RemoteCoverView(title: item.title, imageURL: item.image, hideCover: false)
                                .frame(width: 54, height: 54)
                                .clipShape(.rect(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .lineLimit(2)
                                Text(item.author.isEmpty ? "N/A" : item.author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: AppTheme.cardCornerRadius))
    }
}

private struct FlowLayout: Layout {
    var spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews).rows
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, rows: [Row]) {
        let maxWidth = proposal.width ?? 600
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if current.width + size.width + spacing > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.items.append(RowItem(subview: subview, size: size))
            current.width += size.width + (current.items.count > 1 ? spacing : 0)
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + max(0, Double(rows.count - 1)) * spacing
        return (CGSize(width: width, height: height), rows)
    }

    private struct Row {
        var items: [RowItem] = []
        var width: Double = 0
        var height: Double = 0
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }
}
