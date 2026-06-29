import SwiftUI

struct MeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UserSessionStore.self) private var userSession

    var body: some View {
        let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)

        ScrollView {
            if let user = userSession.user {
                MeContentView(user: user)
                    .padding(AppTheme.contentPadding)
            } else {
                LoginRequiredView(
                    title: "需要登录",
                    message: "登录后可以查看个人资料、云端收藏和签到记录。",
                    action: userSession.presentLogin
                )
                .padding(AppTheme.contentPadding)
            }
        }
        .navigationTitle("我的")
        .task(id: userSession.user?.id) {
            guard userSession.user != nil else { return }
            await userSession.refreshSignInData(endpoint: endpoint)
            await userSession.signInIfNeeded(endpoint: endpoint)
        }
        .toolbar {
            if userSession.user != nil {
                Button("刷新签到", systemImage: "arrow.clockwise") {
                    Task { await userSession.refreshSignInData(endpoint: endpoint) }
                }
                .labelStyle(.iconOnly)
                .disabled(userSession.isLoadingSignInData)
                .help("刷新签到")
            }
        }
    }
}

private struct MeContentView: View {
    let user: UserProfile

    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(DownloadStore.self) private var downloads
    @Environment(PurchasedComicStore.self) private var purchases
    @Environment(UserSessionStore.self) private var userSession

    var body: some View {
        let endpoint = userSession.authenticatedEndpoint(fallback: settings.apiEndpoint)

        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 18) {
                UserAvatarView(user: user)

                VStack(alignment: .leading, spacing: 8) {
                    Text(user.username)
                        .font(.largeTitle)
                        .bold()
                    Text("UID \(user.id)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(signInButtonTitle, systemImage: signInButtonIcon) {
                            Task { await userSession.signIn(endpoint: endpoint) }
                        }
                        .disabled(userSession.isSigningIn || userSession.todaySigned)

                        Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await userSession.logout() }
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], alignment: .leading, spacing: 14) {
                ProfileMetricView(title: "等级", value: "\(user.level) \(user.levelName)")
                ProfileMetricView(title: "经验", value: "\(user.currentLevelExp)/\(user.nextLevelExp)")
                ProfileMetricView(title: "金币", value: user.jCoin.formatted())
                ProfileMetricView(title: "收藏", value: "\(user.currentCollectCount)/\(user.maxCollectCount)")
            }

            AccountAssetsPanelView(user: user, downloads: downloads, purchases: purchases, openFavorites: {
                router.selectRoot(.favorites)
            }, openDownloads: {
                router.selectRoot(.downloads)
            }, openComic: { id in
                router.openComic(id)
            })

            SignInPanelView()
        }
    }

    private var signInButtonTitle: String {
        if userSession.isSigningIn { return "签到中" }
        return userSession.todaySigned ? "已签到" : "签到"
    }

    private var signInButtonIcon: String {
        userSession.todaySigned ? "checkmark.seal.fill" : "checkmark.seal"
    }
}

private struct AccountAssetsPanelView: View {
    let user: UserProfile
    let downloads: DownloadStore
    let purchases: PurchasedComicStore
    let openFavorites: () -> Void
    let openDownloads: () -> Void
    let openComic: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("账号资产", systemImage: "wallet.pass")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], alignment: .leading, spacing: 12) {
                AssetTileView(title: "JCoin 余额", value: user.jCoin.formatted(), systemImage: "creditcard")
                AssetTileView(title: "云端收藏", value: "\(user.currentCollectCount)/\(user.maxCollectCount)", systemImage: "heart")
                AssetTileView(title: "离线章节", value: downloads.completedTasks.count.formatted(), systemImage: "arrow.down.circle")
                AssetTileView(title: "已购作品", value: purchases.items.count.formatted(), systemImage: "cart")
            }

            HStack {
                Button("查看收藏", systemImage: "heart", action: openFavorites)
                Button("查看下载", systemImage: "arrow.down.circle", action: openDownloads)
            }

            if purchases.items.isEmpty {
                Text("打开已购买作品详情后，会自动记录在这里。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("已购列表")
                        .font(.subheadline)
                        .bold()

                    ForEach(purchases.items.prefix(6)) { item in
                        Button {
                            openComic(item.id)
                        } label: {
                            HStack(spacing: 10) {
                                RemoteCoverView(title: item.title, imageURL: item.coverURL, hideCover: false)
                                    .frame(width: 42, height: 56)
                                    .clipShape(.rect(cornerRadius: 5))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .lineLimit(1)
                                    Text(item.author.isEmpty ? "已购" : item.author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if item.price > 0 {
                                    Text("\(item.price) JCoin")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: AppTheme.cardCornerRadius))
    }
}

private struct AssetTileView: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: .rect(cornerRadius: 6))
    }
}

private struct UserAvatarView: View {
    let user: UserProfile

    var body: some View {
        AsyncImage(url: URL(string: user.avatarURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Circle().fill(.quaternary)
                    Text(String(user.username.prefix(2)).uppercased())
                        .font(.title2)
                        .bold()
                }
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
    }
}

private struct ProfileMetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.title3)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: AppTheme.cardCornerRadius))
    }
}

private struct SignInPanelView: View {
    @Environment(UserSessionStore.self) private var userSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("签到", systemImage: "calendar.badge.checkmark")
                    .font(.headline)
                Spacer()
                if userSession.isLoadingSignInData {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let data = userSession.signInData {
                Text(data.eventName.isEmpty ? "连续签到记录" : data.eventName)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(data.records) { record in
                        Label("第 \(record.day) 天", systemImage: record.signed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(record.signed ? .green : .secondary)
                            .lineLimit(1)
                    }
                }
            } else if let error = userSession.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            } else {
                Text("暂未加载签到信息。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: AppTheme.cardCornerRadius))
    }
}
