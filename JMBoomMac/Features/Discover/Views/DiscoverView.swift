import SwiftUI

struct DiscoverView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = DiscoverViewModel()

    var body: some View {
        VStack(spacing: 0) {
            DiscoverToolbar(viewModel: viewModel) {
                Task { await viewModel.reload(endpoint: settings.apiEndpoint) }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        LoadingStateView(title: "正在加载分类")
                    } else if let error = viewModel.errorMessage {
                        ErrorStateView(title: "分类加载失败", message: error) {
                            Task { await viewModel.reload(endpoint: settings.apiEndpoint) }
                        }
                    } else if viewModel.visibleItems.isEmpty {
                        EmptyStateView(title: "暂无分类内容", message: "当前排序或标签没有可展示作品。")
                    } else {
                        ComicGridView(items: viewModel.visibleItems, hideCovers: settings.hideCovers, open: router.openComic)

                        if viewModel.selectedTag == nil, viewModel.items.count < viewModel.total {
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
        .navigationTitle("分类")
        .task {
            await viewModel.load(endpoint: settings.apiEndpoint)
        }
        .onChange(of: viewModel.selectedOrder) { _, _ in
            Task { await viewModel.reload(endpoint: settings.apiEndpoint) }
        }
    }
}

private struct DiscoverToolbar: View {
    @Bindable var viewModel: DiscoverViewModel
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("排序", selection: $viewModel.selectedOrder) {
                    ForEach(CategoryFeedOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                Button("刷新", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.isLoading)
                    .help("刷新")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button(viewModel.selectedTag == nil ? "全部" : "清除筛选", systemImage: "line.3.horizontal.decrease.circle") {
                        viewModel.selectedTag = nil
                    }
                    .buttonStyle(.borderedProminent)

                    ForEach(viewModel.tags, id: \.self) { tag in
                        DiscoverTagButton(
                            tag: tag,
                            isSelected: viewModel.selectedTag == tag,
                            action: { viewModel.toggleTag(tag) }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .padding(AppTheme.contentPadding)
    }
}

private struct DiscoverTagButton: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(tag, action: action)
                .buttonStyle(.borderedProminent)
        } else {
            Button(tag, action: action)
                .buttonStyle(.bordered)
        }
    }
}
