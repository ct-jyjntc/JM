import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var endpointProbes: [ApiEndpointProbe] = []
    private(set) var isDiscoveringEndpoints = false
    private(set) var cacheStats: ReaderCacheStats?
    private(set) var errorMessage: String?

    private let api: JMBoomAPI
    private let reader: ReaderService

    init(api: JMBoomAPI = .shared, reader: ReaderService = .shared) {
        self.api = api
        self.reader = reader
    }

    func configureProxy(settings: AppSettings) {
        Task {
            await api.configureProxy(mode: settings.proxyMode, host: settings.proxyHost, port: settings.proxyPort)
        }
    }

    func discoverEndpoints(settings: AppSettings) async {
        isDiscoveringEndpoints = true
        errorMessage = nil
        defer { isDiscoveringEndpoints = false }

        endpointProbes = await api.discoverEndpoints()
        if let preferred = endpointProbes.first(where: \.available) {
            settings.setEndpoint(preferred.endpoint)
        }
    }

    func loadCacheStats(settings: AppSettings) async {
        do {
            cacheStats = try await reader.cacheStats(cacheLimitBytes: settings.readerCacheLimitBytes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCache(settings: AppSettings) async {
        do {
            cacheStats = try await reader.clearCache(cacheLimitBytes: settings.readerCacheLimitBytes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCacheDirectory() {
        guard let cacheStats else { return }
        NSWorkspace.shared.activateFileViewerSelecting([cacheStats.cacheDirectory])
    }
}
