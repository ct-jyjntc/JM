import Foundation
import Observation

@MainActor
@Observable
final class WeeklyViewModel {
    var selectedSource: RankingSource = .weekly
    private(set) var categories: [WeekCategory] = []
    private(set) var types: [WeekType] = []
    private(set) var rankingCategories: [CategoryDefinition] = []
    var selectedCategoryID = ""
    var selectedTypeID = ""
    var selectedRankingCategorySlug = ""
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
        guard force || categories.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if categories.isEmpty {
                let filters = try await api.weekFilters(endpoint: endpoint)
                categories = filters.categories
                types = filters.types
                selectedCategoryID = categories.first?.id ?? ""
                selectedTypeID = types.first?.id ?? ""
            }
            await loadRankingCategories(endpoint: endpoint)
            try await loadItems(endpoint: endpoint, page: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadItems(endpoint: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await loadItems(endpoint: endpoint, page: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadNext(endpoint: String) async {
        guard !isLoading, items.count < total else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await loadItems(endpoint: endpoint, page: page + 1, appending: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadItems(endpoint: String, page: Int, appending: Bool = false) async throws {
        if selectedSource == .weekly {
            guard !selectedCategoryID.isEmpty, !selectedTypeID.isEmpty else { return }
            let result = try await api.weekItems(endpoint: endpoint, page: page, categoryId: selectedCategoryID, typeId: selectedTypeID)
            self.page = result.page
            total = result.total
            if appending {
                items.append(contentsOf: result.items)
            } else {
                items = result.items
            }
        } else {
            let categorySlug = selectedRankingCategorySlug.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await api.categoryFeed(
                endpoint: endpoint,
                page: page,
                orderRawValue: selectedSource.categoryOrderRawValue,
                categorySlug: categorySlug.isEmpty ? nil : categorySlug
            )
            self.page = result.page
            total = result.total
            if appending {
                items.append(contentsOf: result.items)
            } else {
                items = result.items
            }
        }
    }

    private func loadRankingCategories(endpoint: String) async {
        guard rankingCategories.isEmpty else { return }
        guard let result = try? await api.categoryMetadata(endpoint: endpoint) else { return }
        rankingCategories = result.categories.filter { !$0.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum RankingSource: String, CaseIterable, Identifiable, Sendable {
    case weekly
    case today
    case week
    case month
    case total
    case mostLiked
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "每周推荐"
        case .today: "今日热门"
        case .week: "本周热门"
        case .month: "本月热门"
        case .total: "总热门"
        case .mostLiked: "最多收藏"
        case .images: "最多图片"
        }
    }

    var categoryOrderRawValue: String {
        switch self {
        case .weekly:
            CategoryFeedOrder.latest.rawValue
        case .today:
            "mv_t"
        case .week:
            "mv_w"
        case .month:
            "mv_m"
        case .total:
            "mv"
        case .mostLiked:
            "tf"
        case .images:
            "mp"
        }
    }
}
