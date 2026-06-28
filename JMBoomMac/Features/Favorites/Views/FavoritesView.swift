import SwiftUI

struct FavoritesView: View {
    @Environment(FavoriteStore.self) private var favorites
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PageHeaderView(title: "收藏", subtitle: "本地收藏的作品", isLoading: false) {
                    favorites.clear()
                }

                if favorites.items.isEmpty {
                    EmptyStateView(title: "暂无收藏", message: "在作品详情里点击收藏后会显示在这里。")
                } else {
                    ComicGridView(items: favorites.items.map(\.feedComic), hideCovers: settings.hideCovers, open: router.openComic)
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("收藏")
    }
}

private extension FavoriteItem {
    var feedComic: FeedComic {
        FeedComic(id: id, title: title, author: author, description: "", image: coverUrl, tags: [], updatedAt: nil)
    }
}
