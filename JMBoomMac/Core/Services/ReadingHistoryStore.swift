import Foundation
import Observation

@MainActor
@Observable
final class ReadingHistoryStore {
    private(set) var items: [ReadingHistoryItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func upsert(_ item: ReadingHistoryItem) {
        items.removeAll { $0.comicId == item.comicId }
        items.insert(item, at: 0)
        persist()
    }

    func remove(_ item: ReadingHistoryItem) {
        items.removeAll { $0.comicId == item.comicId }
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private let defaults: UserDefaults
    private let key = "jm-boom.readingHistory"

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ReadingHistoryItem].self, from: data) else {
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
