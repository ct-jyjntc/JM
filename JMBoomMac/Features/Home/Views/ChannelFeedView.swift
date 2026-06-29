import SwiftUI

struct ChannelFeedView: View {
    let route: ChannelRoute

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ChannelFeedViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(title: route.title, subtitle: "频道内容", isLoading: viewModel.isLoading) {
                    Task { await viewModel.load(endpoint: settings.apiEndpoint, id: route.id, force: true) }
                }

                if viewModel.isLoading && viewModel.items.isEmpty {
                    LoadingStateView(title: "正在加载频道")
                } else if let error = viewModel.errorMessage {
                    ErrorStateView(title: "频道加载失败", message: error) {
                        Task { await viewModel.load(endpoint: settings.apiEndpoint, id: route.id, force: true) }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(title: "暂无频道内容", message: "当前频道没有返回可展示作品。")
                } else {
                    ComicGridView(items: viewModel.items, hideCovers: settings.hideCovers, open: router.openComic)

                    if viewModel.items.count < viewModel.total {
                        Button("加载更多", systemImage: "arrow.down.circle") {
                            Task { await viewModel.loadNext(endpoint: settings.apiEndpoint, id: route.id) }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isLoading)
                    }
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle(route.title)
        .task(id: route.id) {
            await viewModel.load(endpoint: settings.apiEndpoint, id: route.id)
        }
    }
}
