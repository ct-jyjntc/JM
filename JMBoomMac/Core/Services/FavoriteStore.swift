import Foundation
import Observation

@MainActor
@Observable
final class FavoriteStore {
    private(set) var items: [FavoriteItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func contains(_ id: String) -> Bool {
        items.contains { $0.id == id }
    }

    func toggle(_ comic: ComicDetail) {
        if contains(comic.id) {
            remove(id: comic.id)
        } else {
            items.insert(
                FavoriteItem(
                    id: comic.id,
                    title: comic.title,
                    author: comic.author.joined(separator: ", "),
                    coverUrl: comic.image,
                    addedAt: .now
                ),
                at: 0
            )
            persist()
        }
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private let defaults: UserDefaults
    private let key = "jm-boom.favorites"

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
