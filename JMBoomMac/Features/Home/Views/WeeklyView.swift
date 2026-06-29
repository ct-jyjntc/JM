import SwiftUI

struct WeeklyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = WeeklyViewModel()

    var body: some View {
        VStack(spacing: 0) {
            WeeklyFiltersView(viewModel: viewModel) {
                Task { await viewModel.reloadItems(endpoint: settings.apiEndpoint) }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        LoadingStateView(title: "正在加载榜单")
                    } else if let error = viewModel.errorMessage {
                        ErrorStateView(title: "榜单加载失败", message: error) {
                            Task { await viewModel.load(endpoint: settings.apiEndpoint, force: true) }
                        }
                    } else if viewModel.items.isEmpty {
                        EmptyStateView(title: "暂无榜单内容", message: "当前筛选没有返回作品。")
                    } else {
                        ComicGridView(items: viewModel.items, hideCovers: settings.hideCovers, open: router.openComic)
                        if viewModel.items.count < viewModel.total {
                            Button("加载更多", systemImage: "arrow.down.circle") {
                                Task { await viewModel.loadNext(endpoint: settings.apiEndpoint) }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(AppTheme.contentPadding)
            }
        }
        .navigationTitle("榜单")
        .task {
            await viewModel.load(endpoint: settings.apiEndpoint)
        }
    }
}

private struct WeeklyFiltersView: View {
    @Bindable var viewModel: WeeklyViewModel
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("榜单", selection: $viewModel.selectedSource) {
                    ForEach(RankingSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 760)

                Button("刷新", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .help("刷新")

                Spacer()
            }

            if viewModel.selectedSource == .weekly {
                HStack {
                    Picker("日期", selection: $viewModel.selectedCategoryID) {
                        ForEach(viewModel.categories) { category in
                            Text(category.label).tag(category.id)
                        }
                    }
                    .frame(maxWidth: 260)

                    Picker("类型", selection: $viewModel.selectedTypeID) {
                        ForEach(viewModel.types) { type in
                            Text(type.title).tag(type.id)
                        }
                    }
                    .frame(maxWidth: 180)

                    Spacer()
                }
            } else {
                HStack {
                    Picker("分类", selection: $viewModel.selectedRankingCategorySlug) {
                        Text("全部分类").tag("")
                        ForEach(viewModel.rankingCategories) { category in
                            Text(category.name).tag(category.slug)
                        }
                    }
                    .frame(maxWidth: 240)

                    Spacer()
                }
            }
        }
        .padding(AppTheme.contentPadding)
        .onChange(of: viewModel.selectedSource) { _, _ in reload() }
        .onChange(of: viewModel.selectedCategoryID) { _, _ in reload() }
        .onChange(of: viewModel.selectedTypeID) { _, _ in reload() }
        .onChange(of: viewModel.selectedRankingCategorySlug) { _, _ in reload() }
    }
}
