import AppKit
import SwiftUI

struct DownloadsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(title: "下载", subtitle: "离线保存的章节", isLoading: downloads.isProcessing) {
                    downloads.openDownloadsFolder()
                }

                if downloads.tasks.isEmpty {
                    EmptyStateView(title: "暂无下载", message: "在作品详情里下载章节或整本后，会显示在这里。")
                } else {
                    HStack {
                        Text("\(downloads.activeTasks.count) 个进行中 · \(downloads.completedTasks.count) 个已完成")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("清除已完成", systemImage: "checkmark.circle") {
                            downloads.clearCompleted(deleteFiles: false)
                        }
                        .disabled(downloads.completedTasks.isEmpty)

                        Button("清除文件", systemImage: "trash", role: .destructive) {
                            downloads.clearCompleted(deleteFiles: true)
                        }
                        .disabled(downloads.completedTasks.isEmpty)
                    }

                    ForEach(downloads.tasks) { task in
                        DownloadTaskRow(
                            task: task,
                            retry: {
                                downloads.retry(id: task.id, cacheLimitBytes: settings.readerCacheLimitBytes)
                            },
                            cancel: {
                                downloads.cancel(id: task.id, cacheLimitBytes: settings.readerCacheLimitBytes)
                            },
                            remove: {
                                downloads.remove(id: task.id)
                            },
                            deleteFiles: {
                                downloads.remove(id: task.id, deleteFiles: true)
                            },
                            openFolder: {
                                guard !task.directoryPath.isEmpty else { return }
                                NSWorkspace.shared.open(URL(fileURLWithPath: task.directoryPath, isDirectory: true))
                            },
                            readOffline: {
                                router.openOfflineDownload(task.id)
                            }
                        )
                    }
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("下载")
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTaskItem
    let retry: () -> Void
    let cancel: () -> Void
    let remove: () -> Void
    let deleteFiles: () -> Void
    let openFolder: () -> Void
    let readOffline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(task.chapterTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(statusTitle, systemImage: statusIcon)
                    .foregroundStyle(statusColor)
            }

            ProgressView(value: task.progress)
            HStack {
                Text("\(task.completedPages)/\(task.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(task.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = task.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("阅读", systemImage: "book") {
                    readOffline()
                }
                .disabled(task.status != .completed || task.pageFilePaths.isEmpty)

                Button("打开文件夹", systemImage: "folder") {
                    openFolder()
                }
                .disabled(task.directoryPath.isEmpty)

                if task.status == .queued || task.status == .downloading {
                    Button("取消", systemImage: "xmark.circle", role: .cancel, action: cancel)
                }

                if task.status == .failed || task.status == .cancelled {
                    Button("重试", systemImage: "arrow.clockwise", action: retry)
                }

                Spacer()

                Menu {
                    Button("仅删除记录", systemImage: "list.bullet.rectangle", action: remove)
                    Button("删除记录和文件", systemImage: "trash", role: .destructive, action: deleteFiles)
                        .disabled(task.directoryPath.isEmpty)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: AppTheme.cardCornerRadius))
    }

    private var statusTitle: String {
        switch task.status {
        case .queued: "排队中"
        case .downloading: "下载中"
        case .completed: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    private var statusIcon: String {
        switch task.status {
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .queued: .secondary
        case .downloading: .blue
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
