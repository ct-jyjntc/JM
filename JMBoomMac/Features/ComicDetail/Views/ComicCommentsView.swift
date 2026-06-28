import SwiftUI

struct ComicCommentsView: View {
    let route: ComicCommentsRoute

    @Environment(AppSettings.self) private var settings
    @State private var viewModel = ComicCommentsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    title: "评论",
                    subtitle: subtitle,
                    isLoading: viewModel.isLoading || viewModel.isLoadingMore
                ) {
                    Task { await viewModel.reload(comicId: route.comicId, endpoint: settings.apiEndpoint) }
                }

                if viewModel.isLoading && viewModel.comments.isEmpty {
                    LoadingStateView(title: "正在加载评论")
                } else if let error = viewModel.errorMessage, viewModel.comments.isEmpty {
                    ErrorStateView(title: "评论加载失败", message: error) {
                        Task { await viewModel.reload(comicId: route.comicId, endpoint: settings.apiEndpoint) }
                    }
                } else if viewModel.comments.isEmpty {
                    EmptyStateView(title: "暂无评论", message: "当前作品还没有返回评论内容。")
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(viewModel.comments) { comment in
                            ComicCommentRowView(comment: comment)
                        }

                        if viewModel.hasMore {
                            Button(viewModel.isLoadingMore ? "加载中" : "加载更多", systemImage: "arrow.down.circle") {
                                Task { await viewModel.loadNext(comicId: route.comicId, endpoint: settings.apiEndpoint) }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(viewModel.isLoadingMore)
                        } else {
                            Text("暂无更多评论")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("评论")
        .toolbar {
            Button("刷新", systemImage: "arrow.clockwise") {
                Task { await viewModel.reload(comicId: route.comicId, endpoint: settings.apiEndpoint) }
            }
            .labelStyle(.iconOnly)
            .disabled(viewModel.isLoading || viewModel.isLoadingMore)
            .help("刷新评论")
        }
        .task(id: route.comicId) {
            await viewModel.load(comicId: route.comicId, endpoint: settings.apiEndpoint)
        }
    }

    private var subtitle: String {
        let total = viewModel.total == 0 ? Int(route.commentTotal) : viewModel.total
        if route.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "共 \(total) 条评论"
        }
        return "\(route.title) · 共 \(total) 条评论"
    }
}

private struct ComicCommentRowView: View {
    let comment: ComicComment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ComicCommentAvatarView(comment: comment)

                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.displayName)
                        .font(.subheadline)
                        .bold()
                    if !comment.time.isEmpty {
                        Text(comment.time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(comment.content.htmlPlainText.nilIfBlank ?? "这条评论没有内容")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        Text("\(reply.displayName)：\(reply.content.htmlPlainText.nilIfBlank ?? "这条回复没有内容")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 6))
            }
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ComicCommentAvatarView: View {
    let comment: ComicComment

    var body: some View {
        AsyncImage(url: URL(string: comment.avatar)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Text(String(comment.displayName.prefix(1)))
                            .font(.caption)
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var htmlPlainText: String {
        var text = replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
