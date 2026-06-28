import Foundation
import Observation

@MainActor
@Observable
final class WeeklyViewModel {
    private(set) var categories: [WeekCategory] = []
    private(set) var types: [WeekType] = []
    var selectedCategoryID = ""
    var selectedTypeID = ""
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
            let filters = try await api.weekFilters(endpoint: endpoint)
            categories = filters.categories
            types = filters.types
            selectedCategoryID = categories.first?.id ?? ""
            selectedTypeID = types.first?.id ?? ""
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
        guard !selectedCategoryID.isEmpty, !selectedTypeID.isEmpty else { return }
        let result = try await api.weekItems(endpoint: endpoint, page: page, categoryId: selectedCategoryID, typeId: selectedTypeID)
        self.page = result.page
        total = result.total
        if appending {
            items.append(contentsOf: result.items)
        } else {
            items = result.items
        }
    }
}
