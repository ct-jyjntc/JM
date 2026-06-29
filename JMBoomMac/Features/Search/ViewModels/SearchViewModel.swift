import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var selectedOrder: CategoryFeedOrder = .latest
    private(set) var items: [SearchAlbum] = []
    private(set) var recentQueries: [String] = []
    private(set) var total = 0
    private(set) var page = 1
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI
    private let defaults: UserDefaults
    private let recentKey = "jm-boom.search.recent"

    init(api: JMBoomAPI = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        recentQueries = defaults.stringArray(forKey: recentKey) ?? []
    }

    func submit(endpoint: String) async {
        page = 1
        await search(endpoint: endpoint, page: 1)
    }

    func loadNext(endpoint: String) async {
        guard !isLoading, items.count < total else { return }
        await search(endpoint: endpoint, page: page + 1, appending: true)
    }

    func useRecentQuery(_ value: String, endpoint: String) async {
        query = value
        await submit(endpoint: endpoint)
    }

    func clearRecentQueries() {
        recentQueries = []
        defaults.removeObject(forKey: recentKey)
    }

    private func search(endpoint: String, page: Int, appending: Bool = false) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            items = []
            total = 0
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await api.search(query: query, page: page, endpoint: endpoint, order: selectedOrder)
            self.page = result.page
            total = result.total
            remember(query)
            if appending {
                items.append(contentsOf: result.items)
            } else {
                items = result.items
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remember(_ query: String) {
        recentQueries.removeAll { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }
        recentQueries.insert(query, at: 0)
        recentQueries = Array(recentQueries.prefix(12))
        defaults.set(recentQueries, forKey: recentKey)
    }
}
