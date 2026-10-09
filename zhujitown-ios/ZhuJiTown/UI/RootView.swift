import SwiftUI

// MARK: - 导航环境

/// 让详情页里的站内链接可以直接 push 到当前的 NavigationStack
struct NavPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath> = .constant(NavigationPath())
}

extension EnvironmentValues {
    var navPath: Binding<NavigationPath> {
        get { self[NavPathKey.self] }
        set { self[NavPathKey.self] = newValue }
    }
}

extension Notification.Name {
    static let siteChanged = Notification.Name("com.zhujitown.siteChanged")
}

// MARK: - 根容器

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    @State private var selection: Tab = .home
    @State private var deepLinkPost: Post?

    enum Tab: Hashable {
        case home, categories, favorites, settings
    }

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("首页", systemImage: "newspaper.fill") }
                .tag(Tab.home)

            CategoriesView()
                .tabItem { Label("分类", systemImage: "square.grid.2x2.fill") }
                .tag(Tab.categories)

            FavoritesView()
                .tabItem { Label("收藏", systemImage: "star.fill") }
                .tag(Tab.favorites)

            SettingsView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(Tab.settings)
        }
        .tint(AppTheme.accent)
        .onOpenURL { handleDeepLink($0) }
        .sheet(item: $deepLinkPost) { post in
            NavigationStack {
                DetailView(post: post)
            }
            .environmentObject(app)
        }
        .overlay(alignment: .top) {
            if let notice = app.notice { noticeBanner(notice) }
        }
    }

    // MARK: URL Scheme / Universal Link

    private func handleDeepLink(_ url: URL) {
        // zhujitown://post/1234
        if url.scheme == AppConfig.urlScheme {
            if let id = ArticleParser.postID(from: url) {
                openPost(id: id)
            }
            return
        }
        // https://www.zhujitown.com/1234.html
        if ArticleParser.isInternalArticle(url.absoluteString),
           let id = ArticleParser.postID(from: url) {
            openPost(id: id)
        }
    }

    private func openPost(id: Int) {
        Task { @MainActor in
            if let cached = Cache.loadPost(id: id) {
                deepLinkPost = cached
            } else {
                do {
                    deepLinkPost = try await WPClient.shared.post(id: id)
                } catch {
                    app.notice = "打开文章失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func noticeBanner(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
            .onTapGesture { app.notice = nil }
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - 主题

enum AppTheme {
    /// 站点主色（橙红，与网页端一致）
    static let accent = Color(red: 0.97, green: 0.40, blue: 0.20)
}
