import Foundation
import Observation

@MainActor
@Observable
final class ComicCommentsViewModel {
    private(set) var comments: [ComicComment] = []
    private(set) var total = 0
    private(set) var page = 1
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?
    private(set) var actionMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    var hasMore: Bool {
        total > 0 ? comments.count < total : comments.count >= 20
    }

    func load(comicId: String, endpoint: String, force: Bool = false) async {
        guard force || comments.isEmpty else { return }
        await loadPage(comicId: comicId, endpoint: endpoint, page: 1, appending: false)
    }

    func reload(comicId: String, endpoint: String) async {
        await loadPage(comicId: comicId, endpoint: endpoint, page: 1, appending: false)
    }

    func loadNext(comicId: String, endpoint: String) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        await loadPage(comicId: comicId, endpoint: endpoint, page: page + 1, appending: true)
    }

    func post(comicId: String, content: String, parentId: String? = nil, endpoint: String) async -> Bool {
        isSubmitting = true
        actionMessage = nil
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let result = try await api.postComicComment(comicId: comicId, content: content, parentId: parentId, endpoint: endpoint)
            actionMessage = result.message.isEmpty ? "评论已发送" : result.message
            await reload(comicId: comicId, endpoint: result.endpoint)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadPage(comicId: String, endpoint: String, page: Int, appending: Bool) async {
        if appending {
            isLoadingMore = true
        } else {
            isLoading = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let result = try await api.comicComments(comicId: comicId, page: page, endpoint: endpoint)
            self.page = result.page
            total = result.total
            if appending {
                comments.append(contentsOf: result.comments)
            } else {
                comments = result.comments
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
