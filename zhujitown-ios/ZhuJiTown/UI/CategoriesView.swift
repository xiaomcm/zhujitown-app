import SwiftUI

/// 分类浏览
struct CategoriesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var target: Int? = nil

    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if app.categories.isEmpty && app.categoriesLoading {
                    LoadingOverlay()
                } else if app.categories.isEmpty {
                    PlaceholderState(
                        systemImage: "square.grid.2x2",
                        title: "还没有分类",
                        subtitle: app.notice,
                        actionTitle: "重新加载"
                    ) {
                        Task { await app.loadCategories(force: true) }
                    }
                } else {
                    content
                }
            }
            .navigationTitle("分类")
            .navigationDestination(item: $target) { id in
                CategoryFeedView(categoryID: id)
            }
            .task {
                if app.categories.isEmpty { await app.loadCategories() }
            }
            .refreshable { await app.loadCategories(force: true) }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(app.categories) { c in
                    Button { target = c.id } label: {
                        CategoryTile(category: c)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            if app.canManage {
                SectionBox(title: "草稿箱") {
                    DraftsView()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct CategoryTile: View {
    let category: Category

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.name)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(category.count) 篇")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(height: 88, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 某个分类的文章流
struct CategoryFeedView: View {
    let categoryID: Int
    @EnvironmentObject private var app: AppModel
    @StateObject private var feed = FeedModel()
    @State private var path = NavigationPath()

    private var name: String {
        app.categories.first { $0.id == categoryID }?.name ?? "分类"
    }

    var body: some View {
        List {
            ForEach(feed.posts) { post in
                NavigationLink(value: post) {
                    PostCardRow(post: post, showCategory: false)
                }
                .task { await feed.loadMoreIfNeeded(current: post) }
            }
            if feed.isLoadingMore {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle(name)
        .navigationDestination(for: Post.self) { DetailView(post: $0) }
        .environment(\.navPath, $path)
        .refreshable { await feed.refresh() }
        .task { await feed.reload(category: categoryID) }
        .overlay {
            if feed.isLoading && feed.posts.isEmpty { LoadingOverlay() }
        }
    }
}

/// 草稿列表（管理员）
struct DraftsView: View {
    @StateObject private var feed = FeedModel()
    @State private var path = NavigationPath()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(feed.posts) { post in
                NavigationLink(value: post) {
                    PostCardRow(post: post)
                }
                .buttonStyle(.plain)
            }
            if feed.posts.isEmpty && !feed.isLoading {
                Text(Prefs.shouldAuthenticate ? "没有草稿" : "请先在「设置」里填入管理凭据")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .environment(\.navPath, $path)
        .navigationDestination(for: Post.self) { DetailView(post: $0) }
        .task {
            feed.includeDrafts = true
            await feed.reload()
        }
    }
}

/// 带标题的分组容器
struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
    }
}
