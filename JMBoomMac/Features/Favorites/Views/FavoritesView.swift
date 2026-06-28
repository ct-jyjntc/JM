import SwiftUI

struct FavoritesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(UserSessionStore.self) private var userSession
    @State private var viewModel = FavoritesViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(title: "收藏", subtitle: "云端收藏的作品", isLoading: viewModel.isLoading) {
                    Task { await viewModel.reload(endpoint: endpoint) }
                }

                if userSession.user == nil {
                    LoginRequiredView(
                        title: "需要登录",
                        message: "登录后可以查看和同步云端收藏。",
                        action: userSession.presentLogin
                    )
                } else if let error = viewModel.errorMessage {
                    ErrorStateView(title: "收藏加载失败", message: error) {
                        Task { await viewModel.reload(endpoint: endpoint) }
                    }
                } else if viewModel.isLoading && viewModel.items.isEmpty {
                    LoadingStateView(title: "正在加载收藏")
                } else {
                    FavoritesToolbar(viewModel: viewModel)

                    if viewModel.items.isEmpty {
                        EmptyStateView(title: "暂无收藏", message: "当前收藏夹没有可展示作品。")
                    } else {
                        ComicGridView(items: viewModel.items, hideCovers: settings.hideCovers, open: router.openComic)
                        FavoritePaginationView(viewModel: viewModel, endpoint: endpoint)
                    }
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("收藏")
        .task(id: "\(userSession.user?.id ?? 0)-\(endpoint)") {
            guard userSession.user != nil else { return }
            await viewModel.load(endpoint: endpoint, force: true)
        }
        .onChange(of: viewModel.selectedFolderId) { _, _ in
            guard userSession.user != nil else { return }
            Task { await viewModel.reload(endpoint: endpoint) }
        }
    }
}

private struct FavoritesToolbar: View {
    @Bindable var viewModel: FavoritesViewModel

    var body: some View {
        HStack {
            Picker("收藏夹", selection: $viewModel.selectedFolderId) {
                ForEach(viewModel.folderOptions) { folder in
                    Text(folder.name.isEmpty ? "收藏夹 \(folder.id)" : folder.name)
                        .tag(folder.id)
                }
            }
            .frame(maxWidth: 260)

            Spacer()

            Text("共 \(viewModel.total) 部作品 · 第 \(viewModel.page) 页")
                .foregroundStyle(.secondary)
        }
    }
}

private struct FavoritePaginationView: View {
    @Bindable var viewModel: FavoritesViewModel
    let endpoint: String

    var body: some View {
        HStack {
            Spacer()
            Button("上一页", systemImage: "chevron.left") {
                Task { await viewModel.loadPrevious(endpoint: endpoint) }
            }
            .disabled(viewModel.page <= 1 || viewModel.isLoading)

            Button("下一页", systemImage: "chevron.right") {
                Task { await viewModel.loadNext(endpoint: endpoint) }
            }
            .disabled(!viewModel.hasMore || viewModel.isLoading)
        }
    }
}
