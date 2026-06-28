import SwiftUI

struct HistoryView: View {
    @Environment(ReadingHistoryStore.self) private var history
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeaderView(title: "历史", subtitle: "继续上次阅读的位置", isLoading: false) {
                history.clear()
            }
            .padding(AppTheme.contentPadding)

            if history.items.isEmpty {
                EmptyStateView(title: "暂无阅读历史", message: "开始阅读后会在这里显示进度。")
            } else {
                List {
                    ForEach(history.items) { item in
                        Button {
                            router.openHistoryItem(item)
                        } label: {
                            HistoryRowView(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                history.remove(item)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("历史")
    }
}

private struct HistoryRowView: View {
    let item: ReadingHistoryItem

    var body: some View {
        HStack(spacing: 12) {
            RemoteCoverView(title: item.title, imageURL: item.coverUrl, hideCover: false)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.chapterTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: Double(item.pageIndex + 1), total: Double(max(1, item.pageCount)))
                    .controlSize(.small)
            }

            Spacer()

            Text(Formatters.progress(pageIndex: item.pageIndex, pageCount: item.pageCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
