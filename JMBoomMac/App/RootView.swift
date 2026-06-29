import SwiftUI

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(UserSessionStore.self) private var userSession
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        @Bindable var userSession = userSession

        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("浏览") {
                    ForEach(SidebarItem.discoveryItems) { item in
                        SidebarRow(item: item)
                            .tag(item.route)
                    }
                }

                Section("个人收藏") {
                    ForEach(SidebarItem.libraryItems) { item in
                        SidebarRow(item: item)
                            .tag(item.route)
                    }
                }

                Section("账户") {
                    ForEach(SidebarItem.accountItems) { item in
                        SidebarRow(item: item)
                            .tag(item.route)
                    }
                }

                Section("应用") {
                    ForEach(SidebarItem.appItems) { item in
                        SidebarRow(item: item)
                            .tag(item.route)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: AppTheme.sidebarWidth, max: 250)
        } detail: {
            DetailRouterView(route: router.route)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button("返回", systemImage: "chevron.left") {
                            router.goBack()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!router.canGoBack)
                        .help("返回上一层")
                    }
                }
        }
        .task {
            await JMBoomAPI.shared.configureProxy(mode: settings.proxyMode, host: settings.proxyHost, port: settings.proxyPort)
            downloads.resumeQueuedDownloads(cacheLimitBytes: settings.readerCacheLimitBytes)
        }
        .sheet(isPresented: $userSession.isLoginPresented) {
            LoginView()
        }
    }

    private var sidebarSelection: Binding<AppRoute?> {
        Binding {
            router.route.rootEquivalent
        } set: { route in
            guard let route else { return }
            router.selectRoot(route)
            if route == .me, userSession.user == nil {
                userSession.presentLogin()
            }
        }
    }
}

private struct SidebarItem: Identifiable {
    let title: String
    let systemImage: String
    let route: AppRoute

    var id: AppRoute {
        route
    }

    static let discoveryItems = [
        SidebarItem(title: "首页", systemImage: "house", route: .home),
        SidebarItem(title: "分类", systemImage: "square.grid.2x2", route: .discover),
        SidebarItem(title: "韩漫", systemImage: "rectangle.stack", route: .hanman),
        SidebarItem(title: "搜索", systemImage: "magnifyingglass", route: .search),
        SidebarItem(title: "榜单", systemImage: "chart.bar", route: .weekly)
    ]

    static let libraryItems = [
        SidebarItem(title: "收藏", systemImage: "heart", route: .favorites),
        SidebarItem(title: "历史", systemImage: "clock", route: .history),
        SidebarItem(title: "下载", systemImage: "arrow.down.circle", route: .downloads)
    ]

    static let accountItems = [
        SidebarItem(title: "我的", systemImage: "person.crop.circle", route: .me)
    ]

    static let appItems = [
        SidebarItem(title: "设置", systemImage: "gearshape", route: .settings)
    ]
}

private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        Label {
            Text(item.title)
                .font(.body)
        } icon: {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 2)
    }
}

private struct DetailRouterView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .home:
            HomeView()
        case .discover:
            DiscoverView()
        case .search:
            SearchView()
        case .weekly:
            WeeklyView()
        case .hanman:
            HanmanView()
        case .favorites:
            FavoritesView()
        case .history:
            HistoryView()
        case .downloads:
            DownloadsView()
        case .me:
            MeView()
        case .settings:
            SettingsView()
        case .comic(let id):
            ComicDetailView(comicId: id)
        case .channel(let route):
            ChannelFeedView(route: route)
        case .comments(let route):
            ComicCommentsView(route: route)
        case .reader(let route):
            ReaderScreen(route: route)
        case .offlineDownload(let id):
            OfflineDownloadReaderView(downloadId: id)
        }
    }
}

private extension AppRoute {
    var rootEquivalent: AppRoute {
        switch self {
        case .comic, .channel, .comments:
            .home
        case .reader:
            .home
        case .offlineDownload:
            .downloads
        default:
            self
        }
    }
}
