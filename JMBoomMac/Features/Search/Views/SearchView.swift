import SwiftUI

struct SearchView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SearchToolbarView(viewModel: viewModel, isLoading: viewModel.isLoading) {
                Task { await viewModel.submit(endpoint: settings.apiEndpoint) }
            } useRecent: { query in
                Task { await viewModel.useRecentQuery(query, endpoint: settings.apiEndpoint) }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        LoadingStateView(title: "正在搜索")
                    } else if let error = viewModel.errorMessage {
                        ErrorStateView(title: "搜索失败", message: error) {
                            Task { await viewModel.submit(endpoint: settings.apiEndpoint) }
                        }
                    } else if viewModel.items.isEmpty {
                        EmptyStateView(title: "输入关键词开始搜索", message: "可以输入标题、作者或 JM ID。")
                    } else {
                        ComicGridView(items: viewModel.items.map(\.feedComic), hideCovers: settings.hideCovers, open: router.openComic)

                        if viewModel.items.count < viewModel.total {
                            Button("加载更多", systemImage: "arrow.down.circle") {
                                Task { await viewModel.loadNext(endpoint: settings.apiEndpoint) }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
                .padding(AppTheme.contentPadding)
            }
        }
        .navigationTitle("搜索")
        .onChange(of: viewModel.selectedOrder) { _, _ in
            guard !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await viewModel.submit(endpoint: settings.apiEndpoint) }
        }
    }
}

private struct SearchToolbarView: View {
    @Bindable var viewModel: SearchViewModel
    let isLoading: Bool
    let submit: () -> Void
    let useRecent: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("搜索漫画", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)

                Button("搜索", systemImage: "magnifyingglass", action: submit)
                    .disabled(isLoading)
            }

            HStack {
                Picker("排序", selection: $viewModel.selectedOrder) {
                    ForEach(CategoryFeedOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                Button("清除历史", systemImage: "trash") {
                    viewModel.clearRecentQueries()
                }
                .disabled(viewModel.recentQueries.isEmpty)
            }

            if !viewModel.recentQueries.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.recentQueries, id: \.self) { query in
                            Button(query) {
                                useRecent(query)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(AppTheme.contentPadding)
    }
}

private extension SearchAlbum {
    var feedComic: FeedComic {
        FeedComic(id: id, title: title, author: author, description: description, image: image, tags: tags, updatedAt: updatedAt)
    }
}
