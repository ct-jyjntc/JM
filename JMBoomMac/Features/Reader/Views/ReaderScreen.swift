import SwiftUI

struct ReaderScreen: View {
    let route: ReaderRoute

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(ReadingHistoryStore.self) private var history
    @State private var viewModel = ReaderViewModel()

    var body: some View {
        ZStack {
            ReaderTheme.background.ignoresSafeArea()

            ReaderContentView(
                route: route,
                viewModel: viewModel,
                endpoint: settings.apiEndpoint,
                shunt: settings.imageShunt,
                cacheLimitBytes: settings.readerCacheLimitBytes,
                prefetchCount: settings.prefetchCount
            )
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("重试", systemImage: "arrow.clockwise") {
                    retry()
                }
                .labelStyle(.iconOnly)
                .disabled(viewModel.isLoadingManifest || viewModel.isLoadingPage)
                .help("刷新当前页")
            }
        }
        .task(id: route.chapterId) {
            await viewModel.load(route: route, endpoint: settings.apiEndpoint, shunt: settings.imageShunt, cacheLimitBytes: settings.readerCacheLimitBytes, prefetchCount: settings.prefetchCount)
            updateHistory()
        }
        .onChange(of: viewModel.currentIndex) { _, _ in
            updateHistory()
        }
        .onChange(of: viewModel.currentChapterId) { _, _ in
            updateHistory()
        }
    }

    private func updateHistory() {
        guard viewModel.pageCount > 0 else { return }
        history.upsert(
            ReadingHistoryItem(
                comicId: route.albumId.isEmpty ? route.chapterId : route.albumId,
                albumId: route.albumId,
                title: route.title,
                author: route.author,
                coverUrl: route.coverURL,
                chapterId: viewModel.currentChapterId.isEmpty ? route.chapterId : viewModel.currentChapterId,
                chapterTitle: viewModel.currentChapterTitle.isEmpty ? route.chapterTitle : viewModel.currentChapterTitle,
                pageIndex: viewModel.currentIndex,
                pageCount: viewModel.pageCount,
                chapters: route.chapters.isEmpty ? nil : route.chapters,
                updatedAt: .now
            )
        )
    }

    private func retry() {
        Task {
            if !viewModel.hasReadableContent {
                await viewModel.load(route: route, endpoint: settings.apiEndpoint, shunt: settings.imageShunt, cacheLimitBytes: settings.readerCacheLimitBytes, prefetchCount: settings.prefetchCount, force: true)
            } else {
                await viewModel.reloadCurrent(endpoint: settings.apiEndpoint, shunt: settings.imageShunt, cacheLimitBytes: settings.readerCacheLimitBytes, prefetchCount: settings.prefetchCount)
            }
        }
    }
}

private struct ReaderContentView: View {
    let route: ReaderRoute
    let viewModel: ReaderViewModel
    let endpoint: String
    let shunt: String
    let cacheLimitBytes: UInt64
    let prefetchCount: Int

    var body: some View {
        if viewModel.isLoadingManifest {
            ProgressView("正在加载阅读信息")
        } else if viewModel.hasReadableContent {
            ReaderPageScrollView(
                viewModel: viewModel,
                endpoint: endpoint,
                shunt: shunt,
                cacheLimitBytes: cacheLimitBytes,
                prefetchCount: prefetchCount
            )
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView {
                Label("阅读加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label("暂无图片", systemImage: "photo")
            }
        }
    }
}

private struct ReaderPageScrollView: View {
    let viewModel: ReaderViewModel
    let endpoint: String
    let shunt: String
    let cacheLimitBytes: UInt64
    let prefetchCount: Int

    @State private var isTrackingVisiblePage = false

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.chapters) { chapter in
                            if chapter.isLoadingManifest {
                                ReaderChapterBoundaryRow(text: "正在加载章节")
                            } else if let message = chapter.errorMessage, chapter.pageCount == 0 {
                                ReaderPageError(message: message) {
                                    Task {
                                        await viewModel.reloadChapter(chapterId: chapter.id, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
                                    }
                                }
                            } else {
                                ForEach(0..<chapter.pageCount, id: \.self) { index in
                                    let anchor = ReaderPageAnchor(chapterId: chapter.id, pageIndex: index)
                                    ReaderPageRow(
                                        chapterId: chapter.id,
                                        index: index,
                                        page: viewModel.page(chapterId: chapter.id, at: index),
                                        isLoading: viewModel.isPageLoading(chapterId: chapter.id, index: index),
                                        errorMessage: viewModel.pageError(chapterId: chapter.id, at: index),
                                        load: {
                                            await viewModel.loadPage(chapterId: chapter.id, index: index, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
                                        },
                                        reload: {
                                            await viewModel.reloadPage(chapterId: chapter.id, index: index, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
                                        }
                                    )
                                    .id(anchor)
                                }
                            }
                        }

                        if viewModel.hasNextChapter {
                            ReaderChapterBoundaryRow(text: "正在接上下一章")
                                .onAppear {
                                    Task {
                                        await viewModel.loadNextChapter(endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: ReaderScrollCoordinateSpace.name)
                .background(ReaderTheme.background)
                .onPreferenceChange(ReaderPageFramePreferenceKey.self) { frames in
                    guard isTrackingVisiblePage else { return }
                    updateCurrentPage(from: frames, viewportHeight: viewport.size.height)
                }
                .task(id: viewModel.initialScrollAnchor) {
                    isTrackingVisiblePage = false
                    await scrollToInitialPage(proxy)
                    try? await Task.sleep(for: .milliseconds(300))
                    isTrackingVisiblePage = true
                }
            }
        }
    }

    private func scrollToInitialPage(_ proxy: ScrollViewProxy) async {
        guard let anchor = viewModel.initialScrollAnchor else { return }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    private func updateCurrentPage(from frames: [ReaderPageFrame], viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        let visibleFrames = frames.filter { frame in
            frame.frame.maxY > 0 && frame.frame.minY < viewportHeight
        }
        guard !visibleFrames.isEmpty else { return }

        let referenceY = min(max(viewportHeight * 0.35, 120), max(0, viewportHeight - 1))
        let aboveReference = visibleFrames.filter { $0.frame.minY <= referenceY }
        let selected = aboveReference.max { $0.frame.minY < $1.frame.minY }
            ?? visibleFrames.min { $0.frame.minY < $1.frame.minY }

        guard let selected else { return }
        viewModel.setCurrentPage(chapterId: selected.anchor.chapterId, index: selected.anchor.pageIndex)
    }
}

private struct ReaderPageRow: View {
    let chapterId: String
    let index: Int
    let page: MaterializedReaderPage?
    let isLoading: Bool
    let errorMessage: String?
    let load: () async -> Void
    let reload: () async -> Void

    var body: some View {
        Group {
            if let page {
                ReaderPageImage(page: page, retry: retry)
            } else if let errorMessage {
                ReaderPageError(message: errorMessage, retry: retry)
            } else {
                ReaderPagePlaceholder(isLoading: isLoading)
            }
        }
        .background(ReaderTheme.background)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ReaderPageFramePreferenceKey.self,
                    value: [
                        ReaderPageFrame(
                            anchor: ReaderPageAnchor(chapterId: chapterId, pageIndex: index),
                            frame: geometry.frame(in: .named(ReaderScrollCoordinateSpace.name))
                        )
                    ]
                )
            }
        }
        .task(id: ReaderPageAnchor(chapterId: chapterId, pageIndex: index)) {
            await load()
        }
    }

    private func retry() {
        Task {
            await reload()
        }
    }
}

private struct ReaderPageImage: View {
    let page: MaterializedReaderPage
    let retry: () -> Void

    var body: some View {
        if let image = NSImage(contentsOf: page.fileURL) {
            GeometryReader { geometry in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.width / page.aspectRatio)
            }
            .aspectRatio(page.aspectRatio, contentMode: .fit)
        } else {
            ReaderPageError(message: "本地图片读取失败。", retry: retry)
        }
    }
}

private struct ReaderPagePlaceholder: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
            }

            Text(isLoading ? "正在准备图片" : "等待加载")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 520)
    }
}

private struct ReaderPageError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label("图片加载失败", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("重试", systemImage: "arrow.clockwise", action: retry)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 520)
    }
}

private struct ReaderChapterBoundaryRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(ReaderTheme.background)
    }
}

private enum ReaderTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
}

private enum ReaderScrollCoordinateSpace {
    static let name = "reader-scroll"
}

private struct ReaderPageFrame: Equatable {
    let anchor: ReaderPageAnchor
    let frame: CGRect
}

private struct ReaderPageFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ReaderPageFrame] = []

    static func reduce(value: inout [ReaderPageFrame], nextValue: () -> [ReaderPageFrame]) {
        value.append(contentsOf: nextValue())
    }
}
