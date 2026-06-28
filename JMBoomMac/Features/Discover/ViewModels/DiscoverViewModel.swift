import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    var selectedOrder: CategoryFeedOrder = .latest
    var selectedTag: String?
    private(set) var items: [FeedComic] = []
    private(set) var page = 1
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    var tags: [String] {
        let discovered = items.flatMap(\.tags)
        let presets = ["同人", "短篇", "韓漫", "單行本", "CG畫集", "Cosplay", "3D"]
        return Array(Set(presets + discovered)).sorted()
    }

    var visibleItems: [FeedComic] {
        guard let selectedTag else { return items }
        return items.filter { $0.tags.contains(selectedTag) }
    }

    func load(endpoint: String, force: Bool = false) async {
        guard force || items.isEmpty else { return }
        await loadPage(endpoint: endpoint, page: 1)
    }

    func reload(endpoint: String) async {
        selectedTag = nil
        await loadPage(endpoint: endpoint, page: 1)
    }

    func loadNext(endpoint: String) async {
        guard !isLoading, items.count < total else { return }
        await loadPage(endpoint: endpoint, page: page + 1, appending: true)
    }

    func toggleTag(_ tag: String) {
        selectedTag = selectedTag == tag ? nil : tag
    }

    private func loadPage(endpoint: String, page: Int, appending: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await api.categoryFeed(endpoint: endpoint, page: page, order: selectedOrder)
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
