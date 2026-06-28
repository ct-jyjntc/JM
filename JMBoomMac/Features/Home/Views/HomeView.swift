import SwiftUI

struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                PageHeaderView(title: "首页", subtitle: "精选漫画作品", isLoading: viewModel.isLoading) {
                    Task { await viewModel.load(endpoint: settings.apiEndpoint, force: true) }
                }

                if viewModel.isLoading && viewModel.sections.isEmpty {
                    LoadingStateView(title: "正在加载首页")
                } else if let error = viewModel.errorMessage {
                    ErrorStateView(title: "信息流加载失败", message: error) {
                        Task { await viewModel.load(endpoint: settings.apiEndpoint, force: true) }
                    }
                } else if viewModel.sections.isEmpty {
                    EmptyStateView(title: "暂无信息流内容", message: "当前接口没有返回可展示的分组。")
                } else {
                    HomeSectionsView(sections: viewModel.sections, hideCovers: settings.hideCovers, open: router.openComic)
                }
            }
            .padding(AppTheme.contentPadding)
        }
        .navigationTitle("首页")
        .task {
            await viewModel.load(endpoint: settings.apiEndpoint)
        }
    }
}

private struct HomeSectionsView: View {
    let sections: [HomeFeedSection]
    let hideCovers: Bool
    let open: (String) -> Void

    var body: some View {
        ForEach(sections) { section in
            Section {
                if section.items.isEmpty {
                    EmptyStateView(title: "暂无内容", message: "当前分组没有返回可展示的漫画。")
                } else {
                    ComicGridView(items: section.items, hideCovers: hideCovers, open: open)
                }
            } header: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.title3)
                        .bold()
                    Text("\(section.items.count) 部作品")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PageHeaderView: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    let refresh: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.largeTitle)
                    .bold()
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let refresh {
                Button("刷新", systemImage: "arrow.clockwise", action: refresh)
                    .labelStyle(.iconOnly)
                    .disabled(isLoading)
                    .help("刷新")
            }
        }
    }
}
