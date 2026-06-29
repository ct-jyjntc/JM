import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DownloadStore {
    private(set) var tasks: [DownloadTaskItem] = []
    private(set) var isProcessing = false
    private(set) var statusMessage: String?

    private let defaults: UserDefaults
    private let service: DownloadService
    private let storageKey = "jm-boom.downloadTasks"
    private var queueTask: Task<Void, Never>?
    private var activeTaskID: String?

    init(defaults: UserDefaults = .standard, service: DownloadService = .shared) {
        self.defaults = defaults
        self.service = service
        load()
    }

    var activeTasks: [DownloadTaskItem] {
        tasks.filter { $0.status == .queued || $0.status == .downloading }
    }

    var completedTasks: [DownloadTaskItem] {
        tasks.filter { $0.status == .completed }
    }

    func task(id: String) -> DownloadTaskItem? {
        tasks.first { $0.id == id }
    }

    func enqueue(_ request: DownloadRequest, cacheLimitBytes: UInt64) {
        let existingStatus = tasks.first { $0.id == request.id }?.status
        if existingStatus == .queued || existingStatus == .downloading {
            statusMessage = "已在下载队列中"
            return
        }

        upsert(
            DownloadTaskItem(
                id: request.id,
                comicId: request.comicId,
                chapterId: request.chapterId,
                title: request.title,
                author: request.author,
                coverURL: request.coverURL,
                chapterTitle: request.chapterTitle,
                endpoint: request.endpoint,
                shunt: request.shunt,
                totalPages: 0,
                completedPages: 0,
                status: .queued,
                directoryPath: "",
                pageFilePaths: [],
                updatedAt: .now,
                errorMessage: nil
            )
        )
        statusMessage = "已加入下载队列"
        processQueue(cacheLimitBytes: cacheLimitBytes)
    }

    func enqueue(_ requests: [DownloadRequest], cacheLimitBytes: UInt64) {
        var insertedCount = 0
        for request in requests {
            let existingStatus = tasks.first { $0.id == request.id }?.status
            guard existingStatus != .queued, existingStatus != .downloading else { continue }
            upsert(
                DownloadTaskItem(
                    id: request.id,
                    comicId: request.comicId,
                    chapterId: request.chapterId,
                    title: request.title,
                    author: request.author,
                    coverURL: request.coverURL,
                    chapterTitle: request.chapterTitle,
                    endpoint: request.endpoint,
                    shunt: request.shunt,
                    totalPages: 0,
                    completedPages: 0,
                    status: .queued,
                    directoryPath: "",
                    pageFilePaths: [],
                    updatedAt: .now,
                    errorMessage: nil
                )
            )
            insertedCount += 1
        }
        if insertedCount == 0 {
            statusMessage = "没有新的下载任务"
        } else {
            statusMessage = insertedCount > 1 ? "已加入 \(insertedCount) 个下载任务" : "已加入下载队列"
        }
        processQueue(cacheLimitBytes: cacheLimitBytes)
    }

    func retry(id: String, cacheLimitBytes: UInt64) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = .queued
        tasks[index].completedPages = 0
        tasks[index].errorMessage = nil
        tasks[index].updatedAt = .now
        persist()
        processQueue(cacheLimitBytes: cacheLimitBytes)
    }

    func resumeQueuedDownloads(cacheLimitBytes: UInt64) {
        guard tasks.contains(where: { $0.status == .queued }) else { return }
        statusMessage = "正在恢复下载队列"
        processQueue(cacheLimitBytes: cacheLimitBytes)
    }

    func cancel(id: String, cacheLimitBytes: UInt64) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        guard tasks[index].status == .queued || tasks[index].status == .downloading else { return }

        tasks[index].status = .cancelled
        tasks[index].errorMessage = nil
        tasks[index].updatedAt = .now
        statusMessage = "已取消下载"
        persist()

        if activeTaskID == id {
            queueTask?.cancel()
        } else {
            processQueue(cacheLimitBytes: cacheLimitBytes)
        }
    }

    func remove(id: String, deleteFiles: Bool = false) {
        if activeTaskID == id {
            queueTask?.cancel()
        }
        let directoryPath = tasks.first { $0.id == id }?.directoryPath ?? ""
        tasks.removeAll { $0.id == id }
        persist()

        if deleteFiles, !directoryPath.isEmpty {
            Task.detached {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: directoryPath, isDirectory: true))
            }
        }
    }

    func clearCompleted(deleteFiles: Bool = false) {
        let directoryPaths = tasks
            .filter { $0.status == .completed }
            .map(\.directoryPath)
            .filter { !$0.isEmpty }
        tasks.removeAll { $0.status == .completed }
        persist()

        if deleteFiles {
            Task.detached {
                for path in directoryPaths {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: path, isDirectory: true))
                }
            }
        }
    }

    func openDownloadsFolder() {
        Task {
            if let url = try? await service.downloadsRoot() {
                await MainActor.run {
                    _ = NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func processQueue(cacheLimitBytes: UInt64) {
        guard !isProcessing else { return }
        isProcessing = true

        queueTask = Task {
            while !Task.isCancelled, let task = tasks.first(where: { $0.status == .queued }) {
                await run(task: task, cacheLimitBytes: cacheLimitBytes)
            }
            activeTaskID = nil
            isProcessing = false
            queueTask = nil

            if tasks.contains(where: { $0.status == .queued }) {
                processQueue(cacheLimitBytes: cacheLimitBytes)
            }
        }
    }

    private func run(task: DownloadTaskItem, cacheLimitBytes: UInt64) async {
        guard let startIndex = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        activeTaskID = task.id
        defer {
            if activeTaskID == task.id {
                activeTaskID = nil
            }
        }
        tasks[startIndex].status = .downloading
        tasks[startIndex].errorMessage = nil
        tasks[startIndex].updatedAt = .now
        persist()

        let request = DownloadRequest(
            comicId: task.comicId,
            chapterId: task.chapterId,
            title: task.title,
            author: task.author,
            coverURL: task.coverURL,
            chapterTitle: task.chapterTitle,
            endpoint: task.endpoint,
            shunt: task.shunt
        )

        do {
            let downloaded = try await service.downloadChapter(request: request, cacheLimitBytes: cacheLimitBytes) { [weak self] completed, total in
                Task { @MainActor in
                    guard let self, let index = self.tasks.firstIndex(where: { $0.id == task.id }), self.tasks[index].status == .downloading else { return }
                    self.tasks[index].totalPages = total
                    self.tasks[index].completedPages = completed
                    self.tasks[index].updatedAt = .now
                    self.persist()
                }
            }

            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
            guard tasks[index].status == .downloading else { return }
            guard downloaded.pageCount > 0, !downloaded.pageFilePaths.isEmpty else {
                tasks[index].status = .failed
                tasks[index].totalPages = downloaded.pageCount
                tasks[index].completedPages = downloaded.pageFilePaths.count
                tasks[index].directoryPath = downloaded.directoryURL.path
                tasks[index].pageFilePaths = downloaded.pageFilePaths
                tasks[index].errorMessage = "下载完成但没有可阅读图片，请重试。"
                tasks[index].updatedAt = .now
                persist()
                return
            }
            tasks[index].status = .completed
            tasks[index].totalPages = downloaded.pageCount
            tasks[index].completedPages = downloaded.pageCount
            tasks[index].directoryPath = downloaded.directoryURL.path
            tasks[index].pageFilePaths = downloaded.pageFilePaths
            tasks[index].errorMessage = nil
            tasks[index].updatedAt = .now
            persist()
        } catch is CancellationError {
            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
            tasks[index].status = .cancelled
            tasks[index].errorMessage = nil
            tasks[index].updatedAt = .now
            persist()
        } catch {
            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
            guard tasks[index].status != .cancelled else { return }
            tasks[index].status = .failed
            tasks[index].errorMessage = error.localizedDescription
            tasks[index].updatedAt = .now
            persist()
        }

    }

    private func upsert(_ task: DownloadTaskItem) {
        tasks.removeAll { $0.id == task.id }
        tasks.insert(task, at: 0)
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DownloadTaskItem].self, from: data) else {
            return
        }
        var didRepair = false
        tasks = decoded.map { task in
            var task = task
            if task.status == .downloading {
                task.status = .queued
                didRepair = true
            }
            if task.status == .completed, !hasReadableDownloadedFiles(task) {
                task.status = .failed
                task.errorMessage = "本地下载文件缺失，请重试下载。"
                task.completedPages = task.pageFilePaths.filter { FileManager.default.fileExists(atPath: $0) }.count
                didRepair = true
            }
            return task
        }
        if didRepair {
            persist()
        }
    }

    private func hasReadableDownloadedFiles(_ task: DownloadTaskItem) -> Bool {
        guard !task.pageFilePaths.isEmpty else { return false }
        if task.totalPages > 0, task.pageFilePaths.count < task.totalPages {
            return false
        }
        return task.pageFilePaths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
