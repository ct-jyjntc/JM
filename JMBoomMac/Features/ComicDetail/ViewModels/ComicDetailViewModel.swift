import Foundation
import Observation

@MainActor
@Observable
final class ComicDetailViewModel {
    private(set) var comic: ComicDetail?
    private(set) var isLoading = false
    private(set) var isTogglingFavorite = false
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?
    private(set) var actionMessage: String?

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

    func toggleFavorite(endpoint: String) async {
        guard let current = comic, !isTogglingFavorite else { return }

        isTogglingFavorite = true
        actionMessage = nil
        defer { isTogglingFavorite = false }

        do {
            let result = try await api.toggleComicFavorite(comicId: current.id, currentFavorite: current.isFavorite, endpoint: endpoint)
            comic?.isFavorite = result.favorited
            actionMessage = result.favorited ? "已添加收藏" : "已取消收藏"
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    func purchase(endpoint: String) async {
        guard let current = comic, !isPurchasing else { return }

        isPurchasing = true
        actionMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await api.purchaseComic(comicId: current.id, endpoint: endpoint)
            let updated = try await api.comicDetail(comicId: current.id, endpoint: result.endpoint)
            comic = updated
            if updated.purchased {
                actionMessage = "购买成功"
            } else {
                let message = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
                actionMessage = message.isEmpty ? "购买状态尚未确认，请在官网完成购买后刷新详情。" : "\(message) 未确认已购状态，请刷新或前往官网完成购买。"
            }
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    func noteOfficialPurchaseFallback() {
        actionMessage = "已打开官网购买页；完成购买后请点刷新购买状态。"
    }
}
