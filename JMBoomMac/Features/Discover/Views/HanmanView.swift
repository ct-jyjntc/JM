import Observation
import SwiftUI

struct HanmanView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = HanmanViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(title: "韩漫", subtitle: "韩漫更新频道", isLoading: viewModel.isLoading) {
                    Task { await viewModel.load(endpoint: settings.apiEndpoint, force: true) }
                }

                Picker("排序", selection: $viewModel.selectedOrder) {
                    ForEach(CategoryFeedOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                if viewModel.isLoading && viewModel.items.isEmpty {
                    LoadingStateView(title: "正在加载韩漫")
                } else if let error = viewModel.errorMessage {
                    ErrorStateView(title: "韩漫加载失败", message: error) {
                        Task { await viewModel.load(endpoint: settings.apiEndpoint, force: true) }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(title: "暂无韩漫内容", message: "当前接口没有返回韩漫频道。")
                } else {
                    ComicGridView(items: viewModel.items, hideCovers: settings.hideCovers, open: router.openComic)

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
        .navigationTitle("韩漫")
        .task {
            await viewModel.load(endpoint: settings.apiEndpoint)
        }
        .onChange(of: viewModel.selectedOrder) { _, _ in
            Task { await viewModel.load(endpoint: settings.apiEndpoint, force: true) }
        }
    }
}

@MainActor
@Observable
private final class HanmanViewModel {
    var selectedOrder: CategoryFeedOrder = .latest
    private(set) var items: [FeedComic] = []
    private(set) var page = 1
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    func load(endpoint: String, force: Bool = false) async {
        guard force || items.isEmpty else { return }
        await loadPage(endpoint: endpoint, page: 1)
    }

    func loadNext(endpoint: String) async {
        guard !isLoading, items.count < total else { return }
        await loadPage(endpoint: endpoint, page: page + 1, appending: true)
    }

    private func loadPage(endpoint: String, page: Int, appending: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await api.categoryFeed(endpoint: endpoint, page: page, order: selectedOrder, categorySlug: "hanman")
            self.page = result.page
            total = result.total
            if appending {
                items.append(contentsOf: result.items)
            } else {
                items = result.items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
