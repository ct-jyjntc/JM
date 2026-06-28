import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var items: [SearchAlbum] = []
    private(set) var total = 0
    private(set) var page = 1
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    func submit(endpoint: String) async {
        page = 1
        await search(endpoint: endpoint, page: 1)
    }

    func loadNext(endpoint: String) async {
        guard !isLoading, items.count < total else { return }
        await search(endpoint: endpoint, page: page + 1, appending: true)
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
            let result = try await api.search(query: query, page: page, endpoint: endpoint)
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
