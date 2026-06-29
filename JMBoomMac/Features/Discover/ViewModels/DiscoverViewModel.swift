import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    var selectedOrder: CategoryFeedOrder = .latest
    var selectedTag: String?
    var selectedCategorySlug: String?
    var selectedCategoryName: String?
    private(set) var categories: [CategoryDefinition] = []
    private(set) var blocks: [CategoryBlock] = []
    private(set) var items: [FeedComic] = []
    private(set) var serverTags: [String] = []
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
        return Array(Set(serverTags + presets + discovered)).sorted()
    }

    var visibleItems: [FeedComic] {
        items
    }

    var selectedCategorySubcategories: [CategoryDefinition.Subcategory] {
        guard let selectedCategorySlug else { return [] }
        return categories.first { $0.slug == selectedCategorySlug }?.subcategories ?? []
    }

    func load(endpoint: String, force: Bool = false) async {
        guard force || items.isEmpty else { return }
        await loadMetadata(endpoint: endpoint)
        await loadPage(endpoint: endpoint, page: 1)
    }

    func reload(endpoint: String) async {
        await loadMetadata(endpoint: endpoint)
        await loadPage(endpoint: endpoint, page: 1)
    }

    func loadNext(endpoint: String) async {
        guard !isLoading, items.count < total else { return }
        await loadPage(endpoint: endpoint, page: page + 1, appending: true)
    }

    func toggleTag(_ tag: String, endpoint: String) async {
        selectedTag = selectedTag == tag ? nil : tag
        await loadPage(endpoint: endpoint, page: 1)
    }

    func selectCategory(_ category: CategoryDefinition, endpoint: String) async {
        selectedTag = nil
        selectedCategorySlug = category.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.slug
        selectedCategoryName = category.name
        await loadPage(endpoint: endpoint, page: 1)
    }

    func clearCategory(endpoint: String) async {
        selectedCategorySlug = nil
        selectedCategoryName = nil
        selectedTag = nil
        await loadPage(endpoint: endpoint, page: 1)
    }

    private func loadPage(endpoint: String, page: Int, appending: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let selectedTag, !selectedTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let result = try await api.search(query: selectedTag, page: page, endpoint: endpoint, order: selectedOrder)
                self.page = result.page
                total = result.total
                let feedItems = result.items.map { item in
                    FeedComic(
                        id: item.id,
                        title: item.title,
                        author: item.author,
                        description: item.description,
                        image: item.image,
                        tags: item.tags,
                        updatedAt: item.updatedAt
                    )
                }
                if appending {
                    items.append(contentsOf: feedItems)
                } else {
                    items = feedItems
                }
            } else {
                let result = try await api.categoryFeed(endpoint: endpoint, page: page, order: selectedOrder, categorySlug: selectedCategorySlug)
                self.page = result.page
                total = result.total
                serverTags = result.tags
                if appending {
                    items.append(contentsOf: result.items)
                } else {
                    items = result.items
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMetadata(endpoint: String) async {
        do {
            let result = try await api.categoryMetadata(endpoint: endpoint)
            categories = result.categories
            blocks = result.blocks
        } catch {
            if categories.isEmpty && blocks.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}
