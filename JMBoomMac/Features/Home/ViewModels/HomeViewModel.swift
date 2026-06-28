import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var sections: [HomeFeedSection] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: JMBoomAPI

    init(api: JMBoomAPI = .shared) {
        self.api = api
    }

    func load(endpoint: String, force: Bool = false) async {
        if isLoading || (!force && !sections.isEmpty) {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            sections = try await api.homeFeed(endpoint: endpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
