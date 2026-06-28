import Foundation
import Observation

@MainActor
@Observable
final class ComicDetailViewModel {
    private(set) var comic: ComicDetail?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    func load(comicId: String, endpoint: String) async {
        if isLoading || comic?.id == comicId {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            comic = try await api.comicDetail(comicId: comicId, endpoint: endpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(comicId: String, endpoint: String) async {
        comic = nil
        await load(comicId: comicId, endpoint: endpoint)
    }
}
