import Foundation
import Observation

@MainActor
@Observable
final class PurchasedComicStore {
    private(set) var items: [PurchasedComicItem] = []

    private let defaults: UserDefaults
    private let storageKey = "jm-boom.purchasedComics"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func remember(_ comic: ComicDetail) {
        guard comic.purchased else { return }

        items.removeAll { $0.id == comic.id }
        items.insert(
            PurchasedComicItem(
                id: comic.id,
                title: comic.title,
                author: comic.author.joined(separator: ", "),
                coverURL: comic.image,
                price: comic.price,
                updatedAt: .now
            ),
            at: 0
        )
        persist()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PurchasedComicItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
