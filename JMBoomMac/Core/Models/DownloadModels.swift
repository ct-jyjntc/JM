import Foundation

enum DownloadStatus: String, Codable, Hashable, Sendable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled
}

struct DownloadTaskItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let comicId: String
    let chapterId: String
    let title: String
    let author: String
    let coverURL: String
    let chapterTitle: String
    let endpoint: String
    let shunt: String
    var totalPages: Int
    var completedPages: Int
    var status: DownloadStatus
    var directoryPath: String
    var pageFilePaths: [String]
    var updatedAt: Date
    var errorMessage: String?

    var progress: Double {
        guard totalPages > 0 else { return status == .completed ? 1 : 0 }
        return min(1, max(0, Double(completedPages) / Double(totalPages)))
    }
}

struct DownloadRequest: Hashable, Sendable {
    let comicId: String
    let chapterId: String
    let title: String
    let author: String
    let coverURL: String
    let chapterTitle: String
    let endpoint: String
    let shunt: String

    var id: String {
        "\(comicId.isEmpty ? chapterId : comicId)-\(chapterId)"
    }
}

struct DownloadedChapter: Hashable, Sendable {
    let directoryURL: URL
    let pageFilePaths: [String]
    let pageCount: Int
}
