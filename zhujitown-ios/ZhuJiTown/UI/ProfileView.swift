import SwiftUI

/// 个人中心（「我的」Tab 根视图）。
/// 展示用户头像 / 昵称 / 邮箱、文章 / 评论 / 收藏统计，并提供
/// 我的文章、我的评论、阅读历史、草稿箱、账号管理、设置等入口。
struct ProfileView: View {
    @EnvironmentObject private var app: AppModel

    @State private var path = NavigationPath()
    @State private var showAccount = false
    @State private var showSettings = false
    @State private var showFavorites = false
    @State private var showLogoutConfirm = false

    /// 个人中心内部导航目标
    private enum Dest: Hashable {
        case posts, comments, history, drafts
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if app.session == nil {
                    notLoggedIn
                } else {
                    loggedIn
                }
            }
            .navigationTitle("个人中心")
            .navigationDestination(for: Post.self) { post in
                DetailView(post: post)
            }
            .navigationDestination(for: Dest.self) { dest in
                switch dest {
                case .posts:    MyPostsView().environmentObject(app)
                case .comments: MyCommentsView().environmentObject(app)
                case .history:  HistoryView().environmentObject(app)
                case .drafts:   DraftsView().environmentObject(app)
                }
            }
            .onChange(of: app.session?.userID) { _ in
                Task { await app.loadMyContent() }
            }
        }
        .accentColor(AppTheme.accent)
        .task { await app.loadMyContent() }
    }

    // MARK: 未登录

    private var notLoggedIn: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("未登录")
                .font(.title3).fontWeight(.semibold)
            Text("登录后可查看我的文章、评论、收藏与阅读历史")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAccount = true
            } label: {
                Text("登录 / 注册").fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .frame(width: 220)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .sheet(isPresented: $showAccount) {
            AccountView().environmentObject(app)
        }
    }

    // MARK: 已登录

    private var loggedIn: some View {
        List {
            headerSection
            statsSection
            contentSection
            accountSection
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showAccount) {
            AccountView().environmentObject(app)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(app)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView().environmentObject(app)
        }
        .alert("确认退出登录？", isPresented: $showLogoutConfirm) {
            Button("取消", role: .cancel) { }
            Button("退出", role: .destructive) {
                Task { await app.logout() }
            }
        }
    }

    private var headerSection: some View {
        Section {
            if let s = app.session {
                HStack(spacing: 14) {
                    avatar(url: s.avatarURL)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.name).font(.headline)
                        if !s.email.isEmpty {
                            Text(s.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !s.roles.isEmpty {
                            Text(s.roles)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.14), in: Capsule())
                                .foregroundStyle(AppTheme.accent)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func avatar(url: String) -> some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                CachedImage(url: u, cornerRadius: 32)
            } else {
                Circle()
                    .fill(AppTheme.accent.opacity(0.18))
                    .overlay(
                        Text(String((app.session?.name ?? "?").prefix(1)).uppercased())
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                    )
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
    }

    private var statsSection: some View {
        Section {
            HStack(spacing: 0) {
                StatTile(count: app.myPostsTotal, title: "文章") {
                    path.append(Dest.posts)
                }
                Divider().frame(height: 36)
                StatTile(count: app.myCommentsTotal, title: "评论") {
                    path.append(Dest.comments)
                }
                Divider().frame(height: 36)
                StatTile(count: app.favoritePosts.count, title: "收藏") {
                    showFavorites = true
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private var contentSection: some View {
        Section("我的内容") {
            menuRow(icon: "doc.text", title: "我的文章", badge: app.myPostsTotal) {
                path.append(Dest.posts)
            }
            menuRow(icon: "bubble.left.and.text", title: "我的评论", badge: app.myCommentsTotal) {
                path.append(Dest.comments)
            }
            menuRow(icon: "clock", title: "阅读历史") {
                path.append(Dest.history)
            }
            if app.canManage {
                menuRow(icon: "pencil.line", title: "草稿箱") {
                    path.append(Dest.drafts)
                }
            }
        }
    }

    private var accountSection: some View {
        Section("账号") {
            menuRow(icon: "person.crop.circle", title: "账号管理") {
                showAccount = true
            }
            menuRow(icon: "gearshape", title: "设置") {
                showSettings = true
            }
            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                menuRowLabel(icon: "rectangle.portrait.and.arrow.right", title: "退出登录", badge: 0)
            }
        }
    }

    // MARK: 行样式

    private func menuRow(icon: String, title: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuRowLabel(icon: icon, title: title, badge: badge)
        }
    }

    @ViewBuilder
    private func menuRowLabel(icon: String, title: String, badge: Int) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(title)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 统计方块

private struct StatTile: View {
    let count: Int
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
