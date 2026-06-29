import Foundation
import Observation

@MainActor
@Observable
final class ChannelFeedViewModel {
    private(set) var items: [FeedComic] = []
    private(set) var page = 1
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    func load(endpoint: String, id: String, force: Bool = false) async {
        guard force || items.isEmpty else { return }
        await loadPage(endpoint: endpoint, id: id, page: 1)
    }

    func loadNext(endpoint: String, id: String) async {
        guard !isLoading, items.count < total else { return }
        await loadPage(endpoint: endpoint, id: id, page: page + 1, appending: true)
    }

    private func loadPage(endpoint: String, id: String, page: Int, appending: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await api.promoteList(endpoint: endpoint, page: page, id: id)
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
