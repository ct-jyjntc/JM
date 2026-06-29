import Foundation

actor DownloadService {
    static let shared = DownloadService(reader: .shared)

    private let reader: ReaderService

    init(reader: ReaderService) {
        self.reader = reader
    }

    func downloadChapter(
        request: DownloadRequest,
        cacheLimitBytes: UInt64,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> DownloadedChapter {
        let manifest = try await reader.manifest(readId: request.chapterId, endpoint: request.endpoint, shunt: request.shunt)
        let target = try chapterDirectory(for: request)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        var pageFilePaths: [String] = []
        for index in manifest.pages.indices {
            try Task.checkCancellation()
            let page = try await reader.materializedPage(
                readId: request.chapterId,
                index: index,
                endpoint: request.endpoint,
                shunt: request.shunt,
                cacheLimitBytes: cacheLimitBytes
            )
            let destination = target.appending(path: String(format: "%04d.%@", index + 1, page.fileURL.pathExtension.isEmpty ? "jpg" : page.fileURL.pathExtension))
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: page.fileURL, to: destination)
            pageFilePaths.append(destination.path)
            onProgress(index + 1, manifest.pages.count)
        }

        return DownloadedChapter(directoryURL: target, pageFilePaths: pageFilePaths, pageCount: manifest.pages.count)
    }

    func downloadsRoot() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "JMBoomMac/downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func chapterDirectory(for request: DownloadRequest) throws -> URL {
        try downloadsRoot()
            .appending(path: safePathSegment("\(request.title)-\(request.chapterTitle)-\(request.chapterId)"), directoryHint: .isDirectory)
    }

    private func safePathSegment(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "chapter" : String(cleaned.prefix(96))
    }
}
