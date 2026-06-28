import Foundation

struct FeedComic: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let description: String
    let image: String
    let tags: [String]
    let updatedAt: Int64?
}

struct HomeFeedSection: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let slug: String
    let type: String
    let filterValue: String
    let items: [FeedComic]
}

struct SearchAlbum: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let description: String
    let image: String
    let tags: [String]
    let href: String
    let updatedAt: Int64?
    let isRedirect: Bool
}

struct ComicDetail: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: [String]
    let description: String
    let totalViews: UInt32
    let likes: UInt32
    let commentTotal: UInt32
    let tags: [String]
    let actors: [String]
    let works: [String]
    var isFavorite: Bool
    let liked: Bool
    let relatedList: [RelatedComic]
    let series: [ComicChapter]
    let seriesId: String
    let price: UInt32
    let purchased: Bool
    let image: String
}

struct RelatedComic: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let image: String
}

struct ComicChapter: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let sort: String
}

struct ReaderChapterReference: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
}

struct ReadingHistoryItem: Identifiable, Codable, Hashable, Sendable {
    var id: String { comicId }

    let comicId: String
    let albumId: String
    let title: String
    let author: String
    let coverUrl: String
    let chapterId: String
    let chapterTitle: String
    let pageIndex: Int
    let pageCount: Int
    let chapters: [ReaderChapterReference]?
    let updatedAt: Date
}

struct FavoriteItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let author: String
    let coverUrl: String
    let addedAt: Date
}

struct ReaderManifest: Hashable, Sendable {
    let endpoint: String
    let readId: String
    let readIdNumber: UInt32
    let shunt: String
    let scrambleId: UInt32
    let speed: String
    let pages: [ReaderPage]
}

struct ReaderPage: Hashable, Sendable {
    let index: Int
    let pageName: String
    let sourceURL: URL
}

struct MaterializedReaderPage: Hashable, Sendable {
    let readId: String
    let index: Int
    let fileURL: URL
    let width: Double
    let height: Double
    let isCached: Bool

    var aspectRatio: Double {
        height == 0 ? 1 : width / height
    }
}
