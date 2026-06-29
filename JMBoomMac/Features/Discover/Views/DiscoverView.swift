import SwiftUI

struct DiscoverView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @State private var viewModel = DiscoverViewModel()

    var body: some View {
        VStack(spacing: 0) {
            DiscoverToolbar(viewModel: viewModel, endpoint: settings.apiEndpoint) {
                Task { await viewModel.reload(endpoint: settings.apiEndpoint) }
            } clearCategory: {
                Task { await viewModel.clearCategory(endpoint: settings.apiEndpoint) }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !viewModel.categories.isEmpty || !viewModel.blocks.isEmpty {
                        OfficialCategoriesView(viewModel: viewModel)
                    }

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        LoadingStateView(title: "正在加载分类")
                    } else if let error = viewModel.errorMessage {
                        ErrorStateView(title: "分类加载失败", message: error) {
                            Task { await viewModel.reload(endpoint: settings.apiEndpoint) }
                        }
                    } else if viewModel.visibleItems.isEmpty {
                        EmptyStateView(title: "暂无分类内容", message: "当前排序或标签没有可展示作品。")
                    } else {
                        ComicGridView(items: viewModel.visibleItems, hideCovers: settings.hideCovers, open: router.openComic)

                        if viewModel.items.count < viewModel.total {
                            Button("加载更多", systemImage: "arrow.down.circle") {
                                Task { await viewModel.loadNext(endpoint: settings.apiEndpoint) }
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(viewModel.isLoading)
                        }
                    }
                }
                .padding(AppTheme.contentPadding)
            }
        }
        .navigationTitle("分类")
        .task {
            await viewModel.load(endpoint: settings.apiEndpoint)
        }
        .onChange(of: viewModel.selectedOrder) { _, _ in
            Task { await viewModel.reload(endpoint: settings.apiEndpoint) }
        }
    }
}

private struct OfficialCategoriesView: View {
    @Bindable var viewModel: DiscoverViewModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !viewModel.categories.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("官方分类")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(viewModel.categories) { category in
                            Button {
                                Task { await viewModel.selectCategory(category, endpoint: settings.apiEndpoint) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(category.name)
                                        .font(.subheadline)
                                        .bold()
                                        .lineLimit(1)
                                    if !category.totalAlbums.isEmpty, category.totalAlbums != "0" {
                                        Text("\(category.totalAlbums) 部")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !category.subcategories.isEmpty {
                                        Text(category.subcategories.map(\.name).prefix(3).joined(separator: " / "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 6))
                            .overlay {
                                if viewModel.selectedCategorySlug == category.slug {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.blue, lineWidth: 1)
                                }
                            }
                        }
                    }
                }

                if !viewModel.selectedCategorySubcategories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("子分类")
                            .font(.subheadline)
                            .bold()
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.selectedCategorySubcategories) { subcategory in
                                    OfficialTagButton(tag: subcategory.name, isSelected: viewModel.selectedTag == subcategory.name) {
                                        Task { await viewModel.toggleTag(subcategory.name, endpoint: settings.apiEndpoint) }
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }

            ForEach(viewModel.blocks) { block in
                VStack(alignment: .leading, spacing: 8) {
                    Text(block.title)
                        .font(.subheadline)
                        .bold()
                    FlowTagLine(tags: block.tags, selectedTag: viewModel.selectedTag) { tag in
                        Task { await viewModel.toggleTag(tag, endpoint: settings.apiEndpoint) }
                    }
                }
            }
        }
    }
}

private struct FlowTagLine: View {
    let tags: [String]
    let selectedTag: String?
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    OfficialTagButton(tag: tag, isSelected: selectedTag == tag) {
                        select(tag)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct OfficialTagButton: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(tag, action: action)
                .buttonStyle(.borderedProminent)
        } else {
            Button(tag, action: action)
                .buttonStyle(.bordered)
        }
    }
}

private struct DiscoverToolbar: View {
    @Bindable var viewModel: DiscoverViewModel
    let endpoint: String
    let reload: () -> Void
    let clearCategory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("排序", selection: $viewModel.selectedOrder) {
                    ForEach(CategoryFeedOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                Button("刷新", systemImage: "arrow.clockwise", action: reload)
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.isLoading)
                    .help("刷新")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button(viewModel.selectedTag == nil && viewModel.selectedCategoryName == nil ? "全部" : "清除筛选", systemImage: "line.3.horizontal.decrease.circle") {
                        clearCategory()
                    }
                    .buttonStyle(.borderedProminent)

                    if let selectedCategoryName = viewModel.selectedCategoryName {
                        Button("分类：\(selectedCategoryName)", systemImage: "xmark.circle", action: clearCategory)
                            .buttonStyle(.borderedProminent)
                    }

                    ForEach(viewModel.tags, id: \.self) { tag in
                        DiscoverTagButton(
                            tag: tag,
                            isSelected: viewModel.selectedTag == tag,
                            action: {
                                Task { await viewModel.toggleTag(tag, endpoint: endpoint) }
                            }
                        )
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .padding(AppTheme.contentPadding)
    }
}

private struct DiscoverTagButton: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(tag, action: action)
                .buttonStyle(.borderedProminent)
        } else {
            Button(tag, action: action)
                .buttonStyle(.bordered)
        }
    }
}
