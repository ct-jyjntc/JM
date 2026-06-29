import Foundation
import Observation

enum ProxyMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case http
    case socks5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "关闭"
        case .http: "HTTP"
        case .socks5: "SOCKS5"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "日间"
        case .dark: "夜间"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let fallbackEndpoints = [
        "https://www.cdnhjk.net",
        "https://www.cdngwc.cc",
        "https://www.cdngwc.net",
        "https://www.cdngwc.club",
        "https://www.cdnutc.me"
    ]
    static let imageShunts = ["1", "2", "3", "4"]
    static let prefetchCounts = [0, 1, 2, 3, 4, 5, 6]
    static let cacheLimitOptionsMB = [128, 256, 512, 1024, 2048]

    private(set) var apiEndpoint: String {
        didSet { persist(apiEndpoint, key: Keys.apiEndpoint) }
    }

    var imageShunt: String {
        didSet { persist(imageShunt, key: Keys.imageShunt) }
    }

    var prefetchCount: Int {
        didSet { persist(prefetchCount, key: Keys.prefetchCount) }
    }

    var readerCacheLimitMB: Int {
        didSet { persist(readerCacheLimitMB, key: Keys.readerCacheLimitMB) }
    }

    var proxyMode: ProxyMode {
        didSet { persist(proxyMode.rawValue, key: Keys.proxyMode) }
    }

    var proxyHost: String {
        didSet { persist(proxyHost, key: Keys.proxyHost) }
    }

    var proxyPort: Int {
        didSet { persist(proxyPort, key: Keys.proxyPort) }
    }

    var hideCovers: Bool {
        didSet { persist(hideCovers, key: Keys.hideCovers) }
    }

    var appearance: AppAppearance {
        didSet { persist(appearance.rawValue, key: Keys.appearance) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        apiEndpoint = Self.normalizedEndpoint(defaults.string(forKey: Keys.apiEndpoint) ?? Self.fallbackEndpoints[0])
        imageShunt = defaults.string(forKey: Keys.imageShunt) ?? "1"
        prefetchCount = defaults.object(forKey: Keys.prefetchCount) as? Int ?? 3
        readerCacheLimitMB = defaults.object(forKey: Keys.readerCacheLimitMB) as? Int ?? 512
        proxyMode = ProxyMode(rawValue: defaults.string(forKey: Keys.proxyMode) ?? "") ?? .off
        proxyHost = defaults.string(forKey: Keys.proxyHost) ?? "127.0.0.1"
        proxyPort = defaults.object(forKey: Keys.proxyPort) as? Int ?? 7890
        hideCovers = defaults.object(forKey: Keys.hideCovers) as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        sanitize()
    }

    func reset() {
        apiEndpoint = Self.fallbackEndpoints[0]
        imageShunt = "1"
        prefetchCount = 3
        readerCacheLimitMB = 512
        proxyMode = .off
        proxyHost = "127.0.0.1"
        proxyPort = 7890
        hideCovers = true
        appearance = .system
    }

    var readerCacheLimitBytes: UInt64 {
        UInt64(readerCacheLimitMB) * 1_024 * 1_024
    }

    private let defaults: UserDefaults

    private func sanitize() {
        if !Self.fallbackEndpoints.contains(apiEndpoint) {
            apiEndpoint = Self.fallbackEndpoints[0]
        }
        if !Self.imageShunts.contains(imageShunt) {
            imageShunt = "1"
        }
        if !Self.prefetchCounts.contains(prefetchCount) {
            prefetchCount = 3
        }
        if !Self.cacheLimitOptionsMB.contains(readerCacheLimitMB) {
            readerCacheLimitMB = 512
        }
        if proxyPort <= 0 || proxyPort > 65_535 {
            proxyPort = 7890
        }
    }

    private func persist(_ value: some Any, key: String) {
        defaults.set(value, forKey: key)
    }

    static func normalizedEndpoint(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/\/+$/, with: "")

        guard !trimmed.isEmpty else { return "" }
        return trimmed.localizedCaseInsensitiveContains("http://") || trimmed.localizedCaseInsensitiveContains("https://")
            ? trimmed
            : "https://\(trimmed)"
    }

    private enum Keys {
        static let apiEndpoint = "jm-boom.apiEndpoint"
        static let imageShunt = "jm-boom.imageShunt"
        static let prefetchCount = "jm-boom.prefetchCount"
        static let readerCacheLimitMB = "jm-boom.readerCacheLimitMB"
        static let proxyMode = "jm-boom.proxyMode"
        static let proxyHost = "jm-boom.proxyHost"
        static let proxyPort = "jm-boom.proxyPort"
        static let hideCovers = "jm-boom.hideCovers"
        static let appearance = "jm-boom.appearance"
    }
}
