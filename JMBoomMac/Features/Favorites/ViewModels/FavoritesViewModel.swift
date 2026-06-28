import Foundation
import Observation

@MainActor
@Observable
final class FavoritesViewModel {
    var selectedFolderId = ""
    private(set) var items: [FeedComic] = []
    private(set) var folders: [FavoriteFolder] = []
    private(set) var page = 1
    private(set) var total = 0
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    var folderOptions: [FavoriteFolder] {
        [FavoriteFolder(id: "", name: "全部收藏")] + folders
    }

    func load(endpoint: String, force: Bool = false) async {
        guard force || items.isEmpty else { return }
        await loadPage(endpoint: endpoint, page: 1)
    }

    func reload(endpoint: String) async {
        await loadPage(endpoint: endpoint, page: 1)
    }

    func loadNext(endpoint: String) async {
        guard hasMore, !isLoading else { return }
        await loadPage(endpoint: endpoint, page: page + 1)
    }

    func loadPrevious(endpoint: String) async {
        guard page > 1, !isLoading else { return }
        await loadPage(endpoint: endpoint, page: page - 1)
    }

    private func loadPage(endpoint: String, page: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await api.favoriteComics(endpoint: endpoint, page: page, folderId: selectedFolderId)
            self.page = result.page
            total = result.total
            hasMore = result.hasMore
            folders = result.folders
            items = result.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
