import Foundation
import Observation

enum AppRoute: Hashable, Sendable {
    case home
    case discover
    case search
    case weekly
    case hanman
    case favorites
    case history
    case downloads
    case me
    case settings
    case comic(String)
    case channel(ChannelRoute)
    case comments(ComicCommentsRoute)
    case reader(ReaderRoute)
    case offlineDownload(String)
}

struct ComicCommentsRoute: Hashable, Sendable {
    let comicId: String
    let title: String
    let commentTotal: UInt32
}

struct ChannelRoute: Hashable, Sendable {
    let id: String
    let title: String
}

struct ReaderRoute: Hashable, Sendable {
    let chapterId: String
    let albumId: String
    let title: String
    let author: String
    let coverURL: String
    let chapterTitle: String
    let initialPageIndex: Int
    let chapters: [ReaderChapterReference]
}

@MainActor
@Observable
final class AppRouter {
    var route: AppRoute = .home
    private(set) var backStack: [AppRoute] = []

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    func selectRoot(_ route: AppRoute) {
        backStack = []
        self.route = route
    }

    func openComic(_ id: String) {
        push(.comic(id))
    }

    func openChannel(id: String, title: String) {
        push(.channel(ChannelRoute(id: id, title: title)))
    }

    func openComments(comicId: String, title: String, commentTotal: UInt32) {
        push(.comments(ComicCommentsRoute(comicId: comicId, title: title, commentTotal: commentTotal)))
    }

    func openReader(_ route: ReaderRoute) {
        push(.reader(route))
    }

    func openOfflineDownload(_ id: String) {
        push(.offlineDownload(id))
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        route = previous
    }

    func openHistoryItem(_ item: ReadingHistoryItem) {
        push(
            .reader(
            ReaderRoute(
                chapterId: item.chapterId,
                albumId: item.albumId,
                title: item.title,
                author: item.author,
                coverURL: item.coverUrl,
                chapterTitle: item.chapterTitle,
                initialPageIndex: item.pageIndex,
                chapters: item.chapters ?? []
            )
            )
        )
    }

    private func push(_ nextRoute: AppRoute) {
        guard nextRoute != route else { return }
        backStack.append(route)
        route = nextRoute
    }
}
