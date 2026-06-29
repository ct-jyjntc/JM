import AppKit
import SwiftUI

struct OfflineDownloadReaderView: View {
    let downloadId: String

    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        Group {
            if let task = downloads.task(id: downloadId), task.status == .completed {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(task.pageFilePaths, id: \.self) { path in
                            LocalReaderPageView(path: path)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .navigationTitle(task.chapterTitle)
                .toolbar {
                    Button("打开文件夹", systemImage: "folder") {
                        guard !task.directoryPath.isEmpty else { return }
                        NSWorkspace.shared.open(URL(fileURLWithPath: task.directoryPath, isDirectory: true))
                    }
                    .labelStyle(.iconOnly)
                    .help("打开文件夹")
                }
            } else {
                EmptyStateView(title: "离线章节不可用", message: "该章节还没有下载完成，或下载记录已经被删除。")
                    .padding(AppTheme.contentPadding)
            }
        }
    }
}

private struct LocalReaderPageView: View {
    let path: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task(id: path) {
            image = NSImage(contentsOfFile: path)
        }
    }
}
