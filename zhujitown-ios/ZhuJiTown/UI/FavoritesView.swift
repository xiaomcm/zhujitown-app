import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var path = NavigationPath()
    @State private var searchText = ""

    private var list: [Post] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return app.favoritePosts }
        let key = searchText.lowercased()
        return app.favoritePosts.filter {
            $0.plainTitle.lowercased().contains(key) || $0.plainExcerpt.lowercased().contains(key)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if list.isEmpty {
                    PlaceholderState(
                        systemImage: app.favoritePosts.isEmpty ? "star" : "magnifyingglass",
                        title: app.favoritePosts.isEmpty ? "还没有收藏" : "没有匹配结果",
                        subtitle: app.favoritePosts.isEmpty ? "在文章页点右上角菜单收藏，离线也能看" : nil
                    )
                } else {
                    List {
                        ForEach(list) { post in
                            NavigationLink(value: post) {
                                PostCardRow(post: post)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    app.toggleFavorite(post)
                                } label: {
                                    Label("取消收藏", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "在收藏中搜索")
                }
            }
            .navigationTitle("收藏")
            .navigationDestination(for: Post.self) { DetailView(post: $0) }
            .environment(\.navPath, $path)
            .task { await app.refreshFavorites() }
            .refreshable { await app.refreshFavorites() }
        }
    }
}
