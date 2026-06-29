import AppKit
import SwiftUI

struct ComicDetailView: View {
    let comicId: String

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(UserSessionStore.self) private var userSession
    @Environment(DownloadStore.self) private var downloads
    @Environment(PurchasedComicStore.self) private var purchases
    @State private var viewModel = ComicDetailViewModel()
    @State private var purchaseSheet: PurchaseSheetContext?

    var body: some View {
        let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && viewModel.comic == nil {
                    LoadingStateView(title: "正在加载详情")
                } else if let error = viewModel.errorMessage {
                    ErrorStateView(title: "详情加载失败", message: error) {
                        Task { await viewModel.refresh(comicId: comicId, endpoint: endpoint) }
                    }
                } else if let comic = viewModel.comic {
                    ComicDetailContentView(
                        comic: comic,
                        isFavoriteBusy: viewModel.isTogglingFavorite,
                        isPurchasing: viewModel.isPurchasing,
                        actionMessage: viewModel.actionMessage,
                        toggleFavorite: toggleFavorite,
                        purchase: purchase,
                        openPurchasePage: {
                            openPurchasePage(comic: comic)
                        },
                        coinBalance: userSession.user?.jCoin,
                        downloadAll: {
                            enqueueDownload(comic: comic, chapters: sortedChapters(comic.series))
                        },
                        downloadChapter: { chapter, title in
                            enqueueDownload(comic: comic, chapters: [chapter], overrideTitle: title)
                        }
                    )
                } else {
                    EmptyStateView(title: "暂无详情", message: "当前作品没有返回可展示的详情。")
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("JM \(comicId)")
        .toolbar {
            Button("刷新", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh(comicId: comicId, endpoint: endpoint) }
            }
            .labelStyle(.iconOnly)
            .help("刷新")
        }
        .task(id: comicId) {
            await viewModel.load(comicId: comicId, endpoint: endpoint)
        }
        .onChange(of: viewModel.comic) { _, comic in
            if let comic {
                purchases.remember(comic)
            }
        }
        .sheet(item: $purchaseSheet) { context in
            PurchaseWebView(
                comicTitle: context.comic.title,
                url: context.url,
                relatedCookieURLs: [URL(string: endpoint)].compactMap(\.self),
                refreshStatus: {
                    let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)
                    await viewModel.refresh(comicId: context.comic.id, endpoint: endpoint)
                    await userSession.refreshSignInData(endpoint: endpoint)

                    if viewModel.comic?.purchased == true {
                        return "已同步购买状态。"
                    }
                    return "已刷新详情；如果刚在官网完成购买，可能需要稍后再刷新。"
                },
                persistCookies: {
                    let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)
                    await userSession.persistCurrentCookies(endpoint: endpoint)
                },
                openExternal: {
                    NSWorkspace.shared.open(context.url)
                }
            )
        }
    }

    private func toggleFavorite() {
        guard userSession.user != nil else {
            userSession.presentLogin()
            return
        }

        Task {
            await viewModel.toggleFavorite(endpoint: userSession.authenticatedEndpoint(fallback: settings.apiEndpoint))
        }
    }

    private func purchase() {
        guard userSession.user != nil else {
            userSession.presentLogin()
            return
        }

        Task {
            let currentComic = viewModel.comic
            await viewModel.purchase(endpoint: userSession.authenticatedEndpoint(fallback: settings.apiEndpoint))
            await userSession.refreshSignInData(endpoint: userSession.authenticatedEndpoint(fallback: settings.apiEndpoint))
            await userSession.persistCurrentCookies(endpoint: userSession.authenticatedEndpoint(fallback: settings.apiEndpoint))

            let refreshedComic = viewModel.comic ?? currentComic
            if let refreshedComic, refreshedComic.price > 0, !refreshedComic.purchased {
                viewModel.noteOfficialPurchaseFallback()
                openPurchasePage(comic: refreshedComic)
            }
        }
    }

    private func openPurchasePage(comic: ComicDetail) {
        guard let url = URL(string: "https://18comic.vip/album/\(comic.id)") else { return }
        purchaseSheet = PurchaseSheetContext(comic: comic, url: url)
    }

    private func enqueueDownload(comic: ComicDetail, chapters: [ComicChapter], overrideTitle: String? = nil) {
        let albumId = comic.seriesId.isEmpty ? comic.id : comic.seriesId
        let author = comic.author.joined(separator: ", ")
        let ordered = sortedChapters(comic.series)
        let requests = chapters.map { chapter in
            let chapterTitle = overrideTitle ?? chapterTitle(for: chapter, in: ordered)
            return DownloadRequest(
                comicId: albumId,
                chapterId: chapter.id,
                title: comic.title,
                author: author,
                coverURL: comic.image,
                chapterTitle: chapterTitle,
                endpoint: userSession.authenticatedEndpoint(fallback: settings.apiEndpoint),
                shunt: settings.imageShunt
            )
        }

        downloads.enqueue(requests, cacheLimitBytes: settings.readerCacheLimitBytes)
    }
}

private struct PurchaseSheetContext: Identifiable {
    var id: String { comic.id }

    let comic: ComicDetail
    let url: URL
}

private struct ComicDetailContentView: View {
    let comic: ComicDetail
    let isFavoriteBusy: Bool
    let isPurchasing: Bool
    let actionMessage: String?
    let toggleFavorite: () -> Void
    let purchase: () -> Void
    let openPurchasePage: () -> Void
    let coinBalance: UInt32?
    let downloadAll: () -> Void
    let downloadChapter: (ComicChapter, String) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ComicHeroView(
                comic: comic,
                hideCover: settings.hideCovers,
                isFavorite: comic.isFavorite,
                isFavoriteBusy: isFavoriteBusy,
                isPurchasing: isPurchasing,
                actionMessage: actionMessage,
                toggleFavorite: toggleFavorite,
                purchase: purchase,
                openPurchasePage: openPurchasePage,
                coinBalance: coinBalance,
                downloadAll: downloadAll,
                showComments: {
                    router.openComments(comicId: comic.id, title: comic.title, commentTotal: comic.commentTotal)
                }
            )

            HStack(alignment: .top, spacing: 24) {
                ChaptersView(comic: comic, download: downloadChapter) { chapter, chapterTitle, chapters in
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
    let isFavoriteBusy: Bool
    let isPurchasing: Bool
    let actionMessage: String?
    let toggleFavorite: () -> Void
    let purchase: () -> Void
    let openPurchasePage: () -> Void
    let coinBalance: UInt32?
    let downloadAll: () -> Void
    let showComments: () -> Void

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

                HStack {
                    Button(isFavoriteBusy ? "处理中" : (isFavorite ? "取消收藏" : "收藏"), systemImage: isFavorite ? "heart.fill" : "heart", action: toggleFavorite)
                        .disabled(isFavoriteBusy)

                    Button("评论", systemImage: "bubble", action: showComments)

                    Button("下载整本", systemImage: "arrow.down.circle", action: downloadAll)

                    if comic.price > 0, !comic.purchased {
                        Button(isPurchasing ? "购买中" : "购买", systemImage: "cart", action: purchase)
                            .disabled(isPurchasing)

                        Button("官网购买", systemImage: "safari", action: openPurchasePage)
                    }
                }

                if comic.price > 0 {
                    let balance = coinBalance.map { " · 余额 \($0) JCoin" } ?? ""
                    Label(comic.purchased ? "已购买" : "需 \(comic.price) JCoin\(balance)", systemImage: comic.purchased ? "checkmark.seal" : "cart")
                        .font(.subheadline)
                        .foregroundStyle(comic.purchased ? .green : .secondary)
                }

                if let actionMessage, !actionMessage.isEmpty {
                    Text(actionMessage)
                        .font(.footnote)
                        .foregroundStyle(actionMessage.contains("失败") ? .red : .secondary)
                }

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
    let download: (ComicChapter, String) -> Void
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

                        HStack(spacing: 6) {
                            Button {
                                open(indexed.chapter, chapterTitle, readerChapters)
                            } label: {
                                Label(chapterTitle, systemImage: "book")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button("下载", systemImage: "arrow.down.circle") {
                                download(indexed.chapter, chapterTitle)
                            }
                            .labelStyle(.iconOnly)
                            .help("下载 \(chapterTitle)")
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

private func chapterTitle(for chapter: ComicChapter, in orderedChapters: [ComicChapter]) -> String {
    let index = orderedChapters.firstIndex { $0.id == chapter.id } ?? 0
    return formatChapterTitle(chapter, index: index)
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
