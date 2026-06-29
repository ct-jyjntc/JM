import SwiftUI

struct ComicCommentsView: View {
    let route: ComicCommentsRoute

    @Environment(AppSettings.self) private var settings
    @Environment(UserSessionStore.self) private var userSession
    @State private var viewModel = ComicCommentsViewModel()
    @State private var draft = ""
    @State private var replyTarget: ComicComment?

    var body: some View {
        let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(
                    title: "评论",
                    subtitle: subtitle,
                    isLoading: viewModel.isLoading || viewModel.isLoadingMore
                ) {
                    Task { await viewModel.reload(comicId: route.comicId, endpoint: endpoint) }
                }

                CommentComposerView(
                    draft: $draft,
                    replyTargetName: replyTarget?.displayName,
                    isSubmitting: viewModel.isSubmitting,
                    submit: {
                        submitComment(endpoint: endpoint)
                    },
                    cancelReply: {
                        replyTarget = nil
                    }
                )

                if let message = viewModel.actionMessage, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.errorMessage, !error.isEmpty, !viewModel.comments.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.isLoading && viewModel.comments.isEmpty {
                    LoadingStateView(title: "正在加载评论")
                } else if let error = viewModel.errorMessage, viewModel.comments.isEmpty {
                    ErrorStateView(title: "评论加载失败", message: error) {
                        Task { await viewModel.reload(comicId: route.comicId, endpoint: endpoint) }
                    }
                } else if viewModel.comments.isEmpty {
                    EmptyStateView(title: "暂无评论", message: "当前作品还没有返回评论内容。")
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(viewModel.comments) { comment in
                            ComicCommentRowView(
                                comment: comment,
                                reply: { comment in
                                    beginReply(to: comment)
                                }
                            )
                        }

                        if viewModel.hasMore {
                            Button(viewModel.isLoadingMore ? "加载中" : "加载更多", systemImage: "arrow.down.circle") {
                                Task { await viewModel.loadNext(comicId: route.comicId, endpoint: endpoint) }
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
                Task { await viewModel.reload(comicId: route.comicId, endpoint: endpoint) }
            }
            .labelStyle(.iconOnly)
            .disabled(viewModel.isLoading || viewModel.isLoadingMore)
            .help("刷新评论")
        }
        .task(id: route.comicId) {
            await viewModel.load(comicId: route.comicId, endpoint: endpoint)
        }
    }

    private var subtitle: String {
        let total = viewModel.total == 0 ? Int(route.commentTotal) : viewModel.total
        if route.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "共 \(total) 条评论"
        }
        return "\(route.title) · 共 \(total) 条评论"
    }

    private func submitComment(endpoint: String) {
        guard userSession.user != nil else {
            userSession.presentLogin()
            return
        }

        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        Task {
            let sent = await viewModel.post(comicId: route.comicId, content: content, parentId: replyTarget?.id, endpoint: endpoint)
            if sent {
                draft = ""
                replyTarget = nil
            }
        }
    }

    private func beginReply(to comment: ComicComment) {
        guard userSession.user != nil else {
            userSession.presentLogin()
            return
        }
        replyTarget = comment
    }
}

private struct ComicCommentRowView: View {
    let comment: ComicComment
    let reply: (ComicComment) -> Void

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

            HStack(spacing: 12) {
                Label("\(comment.likeCount)", systemImage: "hand.thumbsup")
                    .foregroundStyle(.secondary)

                Button("回复", systemImage: "arrowshape.turn.up.left") {
                    reply(comment)
                }
            }
            .font(.subheadline)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(comment.replies) { reply in
                        CommentReplyView(
                            comment: reply,
                            reply: {
                                self.reply(reply)
                            }
                        )
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

private struct CommentReplyView: View {
    let comment: ComicComment
    let reply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(comment.displayName)：\(comment.content.htmlPlainText.nilIfBlank ?? "这条回复没有内容")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label("\(comment.likeCount)", systemImage: "hand.thumbsup")
                    .foregroundStyle(.secondary)
                Button("回复", systemImage: "arrowshape.turn.up.left", action: reply)
            }
            .font(.caption)
        }
    }
}

private struct CommentComposerView: View {
    @Binding var draft: String
    let replyTargetName: String?
    let isSubmitting: Bool
    let submit: () -> Void
    let cancelReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTargetName {
                HStack {
                    Text("回复 \(replyTargetName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("取消", systemImage: "xmark.circle", action: cancelReply)
                        .labelStyle(.iconOnly)
                }
            }

            TextEditor(text: $draft)
                .frame(minHeight: 76)
                .padding(8)
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 6))

            HStack {
                Spacer()
                Button(isSubmitting ? "发送中" : "发送评论", systemImage: "paperplane", action: submit)
                    .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
