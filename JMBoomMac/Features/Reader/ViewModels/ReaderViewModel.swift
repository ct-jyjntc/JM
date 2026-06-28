import Foundation
import Observation

struct ReaderPageAnchor: Hashable, Sendable {
    let chapterId: String
    let pageIndex: Int
}

struct ReaderLoadedChapter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let catalogIndex: Int
    var manifest: ReaderManifest?
    var pages: [Int: MaterializedReaderPage] = [:]
    var loadingPageIndexes: Set<Int> = []
    var failedPageMessages: [Int: String] = [:]
    var isLoadingManifest = false
    var errorMessage: String?

    var pageCount: Int {
        manifest?.pages.count ?? 0
    }
}

@MainActor
@Observable
final class ReaderViewModel {
    private(set) var chapters: [ReaderLoadedChapter] = []
    private(set) var chapterCatalog: [ReaderChapterReference] = []
    private(set) var currentChapterId = ""
    private(set) var currentIndex = 0
    private(set) var initialScrollAnchor: ReaderPageAnchor?
    private(set) var isInitialLoading = false
    private(set) var errorMessage: String?

    private var loadingChapterIds: Set<String> = []
    private let reader: ReaderService

    init(reader: ReaderService = .shared) {
        self.reader = reader
    }

    var pageCount: Int {
        currentChapter?.pageCount ?? 0
    }

    var currentChapterTitle: String {
        currentChapter?.title ?? currentReference?.title ?? ""
    }

    var isLoadingManifest: Bool {
        isInitialLoading
    }

    var isLoadingPage: Bool {
        chapters.contains { !$0.loadingPageIndexes.isEmpty }
    }

    var hasReadableContent: Bool {
        chapters.contains { $0.pageCount > 0 || $0.isLoadingManifest }
    }

    var hasNextChapter: Bool {
        guard let last = chapters.last else { return false }
        return chapterCatalog.indices.contains(last.catalogIndex + 1)
    }

    var nextChapterTitle: String {
        guard let last = chapters.last, chapterCatalog.indices.contains(last.catalogIndex + 1) else {
            return "下一章"
        }
        return chapterCatalog[last.catalogIndex + 1].title
    }

    func page(chapterId: String, at index: Int) -> MaterializedReaderPage? {
        chapter(with: chapterId)?.pages[index]
    }

    func isPageLoading(chapterId: String, index: Int) -> Bool {
        chapter(with: chapterId)?.loadingPageIndexes.contains(index) ?? false
    }

    func pageError(chapterId: String, at index: Int) -> String? {
        chapter(with: chapterId)?.failedPageMessages[index]
    }

    func load(route: ReaderRoute, endpoint: String, shunt: String, cacheLimitBytes: UInt64, prefetchCount: Int, force: Bool = false) async {
        if !force, currentChapterId == route.chapterId, !chapters.isEmpty {
            currentIndex = clampedIndex(route.initialPageIndex, in: route.chapterId)
            initialScrollAnchor = ReaderPageAnchor(chapterId: route.chapterId, pageIndex: currentIndex)
            await loadPage(chapterId: currentChapterId, index: currentIndex, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
            return
        }

        chapterCatalog = normalizedCatalog(for: route)
        let catalogIndex = chapterCatalog.firstIndex { $0.id == route.chapterId } ?? 0
        let current = chapterCatalog[catalogIndex]
        currentChapterId = current.id
        currentIndex = max(0, route.initialPageIndex)
        chapters = [ReaderLoadedChapter(id: current.id, title: current.title, catalogIndex: catalogIndex)]
        loadingChapterIds = []
        errorMessage = nil
        isInitialLoading = true

        await loadManifest(chapterId: current.id, endpoint: endpoint, shunt: shunt)
        currentIndex = clampedIndex(currentIndex, in: current.id)
        initialScrollAnchor = ReaderPageAnchor(chapterId: current.id, pageIndex: currentIndex)
        await loadPage(chapterId: current.id, index: currentIndex, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
        isInitialLoading = false
    }

    func reloadCurrent(endpoint: String, shunt: String, cacheLimitBytes: UInt64, prefetchCount: Int) async {
        await reloadPage(chapterId: currentChapterId, index: currentIndex, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
    }

    func reloadChapter(chapterId: String, endpoint: String, shunt: String, cacheLimitBytes: UInt64, prefetchCount: Int) async {
        guard let chapterIndex = chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        chapters[chapterIndex].manifest = nil
        chapters[chapterIndex].pages = [:]
        chapters[chapterIndex].loadingPageIndexes = []
        chapters[chapterIndex].failedPageMessages = [:]
        chapters[chapterIndex].errorMessage = nil

        await loadManifest(chapterId: chapterId, endpoint: endpoint, shunt: shunt)
        let targetIndex = chapterId == currentChapterId ? currentIndex : 0
        await loadPage(chapterId: chapterId, index: targetIndex, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
    }

    func reloadPage(chapterId: String, index: Int, endpoint: String, shunt: String, cacheLimitBytes: UInt64, prefetchCount: Int) async {
        guard let chapterIndex = chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        chapters[chapterIndex].pages[index] = nil
        chapters[chapterIndex].failedPageMessages[index] = nil
        await loadPage(chapterId: chapterId, index: index, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
    }

    func loadPage(chapterId: String, index: Int, endpoint: String, shunt: String, cacheLimitBytes: UInt64, prefetchCount: Int) async {
        guard let chapterIndex = chapters.firstIndex(where: { $0.id == chapterId }),
              let manifest = chapters[chapterIndex].manifest,
              manifest.pages.indices.contains(index),
              chapters[chapterIndex].pages[index] == nil,
              !chapters[chapterIndex].loadingPageIndexes.contains(index) else {
            return
        }

        chapters[chapterIndex].loadingPageIndexes.insert(index)
        chapters[chapterIndex].failedPageMessages[index] = nil
        if chapters[chapterIndex].pages.isEmpty {
            chapters[chapterIndex].errorMessage = nil
        }

        do {
            let page = try await reader.materializedPage(readId: manifest.readId, index: index, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes)
            if let updatedIndex = chapters.firstIndex(where: { $0.id == chapterId }) {
                chapters[updatedIndex].pages[index] = page
                chapters[updatedIndex].loadingPageIndexes.remove(index)
            }
            if prefetchCount > 0 {
                Task {
                    await reader.prefetch(readId: manifest.readId, centerIndex: index, radius: prefetchCount, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes)
                }
            }
        } catch {
            if let updatedIndex = chapters.firstIndex(where: { $0.id == chapterId }) {
                chapters[updatedIndex].failedPageMessages[index] = error.localizedDescription
                if chapters[updatedIndex].pages.isEmpty {
                    chapters[updatedIndex].errorMessage = error.localizedDescription
                    errorMessage = error.localizedDescription
                }
                chapters[updatedIndex].loadingPageIndexes.remove(index)
            }
        }
    }

    func setCurrentPage(chapterId: String, index: Int) {
        guard chapterCatalog.contains(where: { $0.id == chapterId }) else { return }
        let nextIndex = clampedIndex(index, in: chapterId)
        guard currentChapterId != chapterId || currentIndex != nextIndex else { return }
        currentChapterId = chapterId
        currentIndex = nextIndex
    }

    func loadNextChapter(endpoint: String, shunt: String, cacheLimitBytes: UInt64, prefetchCount: Int) async {
        guard let last = chapters.last, chapterCatalog.indices.contains(last.catalogIndex + 1) else { return }
        let reference = chapterCatalog[last.catalogIndex + 1]
        guard !chapters.contains(where: { $0.id == reference.id }), !loadingChapterIds.contains(reference.id) else { return }

        loadingChapterIds.insert(reference.id)
        chapters.append(ReaderLoadedChapter(id: reference.id, title: reference.title, catalogIndex: last.catalogIndex + 1, isLoadingManifest: true))
        await loadManifest(chapterId: reference.id, endpoint: endpoint, shunt: shunt)
        await loadPage(chapterId: reference.id, index: 0, endpoint: endpoint, shunt: shunt, cacheLimitBytes: cacheLimitBytes, prefetchCount: prefetchCount)
        loadingChapterIds.remove(reference.id)
    }

    private var currentChapter: ReaderLoadedChapter? {
        chapter(with: currentChapterId)
    }

    private var currentReference: ReaderChapterReference? {
        chapterCatalog.first { $0.id == currentChapterId }
    }

    private func chapter(with id: String) -> ReaderLoadedChapter? {
        chapters.first { $0.id == id }
    }

    private func loadManifest(chapterId: String, endpoint: String, shunt: String) async {
        guard let chapterIndex = chapters.firstIndex(where: { $0.id == chapterId }),
              chapters[chapterIndex].manifest == nil else {
            return
        }

        chapters[chapterIndex].isLoadingManifest = true
        chapters[chapterIndex].errorMessage = nil

        do {
            let manifest = try await reader.manifest(readId: chapterId, endpoint: endpoint, shunt: shunt)
            if let updatedIndex = chapters.firstIndex(where: { $0.id == chapterId }) {
                chapters[updatedIndex].manifest = manifest
                chapters[updatedIndex].isLoadingManifest = false
                chapters[updatedIndex].errorMessage = nil
            }
        } catch {
            if let updatedIndex = chapters.firstIndex(where: { $0.id == chapterId }) {
                chapters[updatedIndex].isLoadingManifest = false
                chapters[updatedIndex].errorMessage = error.localizedDescription
            }
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedCatalog(for route: ReaderRoute) -> [ReaderChapterReference] {
        var catalog = route.chapters.filter { !$0.id.isEmpty }
        if !catalog.contains(where: { $0.id == route.chapterId }) {
            catalog.insert(ReaderChapterReference(id: route.chapterId, title: route.chapterTitle), at: 0)
        }
        return catalog.isMostlyDescendingByTitleNumber ? catalog.reversed() : catalog
    }

    private func clampedIndex(_ index: Int, in chapterId: String) -> Int {
        guard let pageCount = chapter(with: chapterId)?.pageCount, pageCount > 0 else {
            return max(0, index)
        }
        return min(max(0, index), pageCount - 1)
    }
}

private extension Array where Element == ReaderChapterReference {
    var isMostlyDescendingByTitleNumber: Bool {
        let numbers = compactMap { $0.title.firstInteger }
        guard numbers.count >= 2 else { return false }

        var descendingPairs = 0
        var ascendingPairs = 0
        for pair in zip(numbers, numbers.dropFirst()) {
            if pair.0 > pair.1 {
                descendingPairs += 1
            } else if pair.0 < pair.1 {
                ascendingPairs += 1
            }
        }
        return descendingPairs > ascendingPairs
    }
}

private extension String {
    var firstInteger: Int? {
        var digits = ""
        for scalar in unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                digits.unicodeScalars.append(scalar)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }
}
