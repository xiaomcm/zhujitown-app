import Foundation
import SwiftUI

/// 全局状态：分类、收藏、管理员模式
@MainActor
final class AppModel: ObservableObject {

    @Published var categories: [Category] = []
    @Published var favoritePosts: [Post] = []
    @Published var favoriteIDs: Set<Int> = []
    @Published var categoriesLoading = false
    @Published var notice: String?

    // MARK: 账号（用户在 App 内登录，工程不再内置任何管理员凭据）

    @Published var session: Session? {
        didSet { Prefs.session = session }
    }
    @Published var pluginReady = false
    @Published var registrationOpen = false
    @Published var authBusy = false
    @Published var authError: String?
    @Published var authNotice: String?

    /// 当前登录用户是否具备编辑以上权限（可看草稿）
    var canManage: Bool { session?.canManage ?? false }

    init() {
        Prefs.registerDefaults()
        Cache.prepare()
        session = Prefs.session
    }

    func bootstrap() async {
        await probeAuth()
        await loadCategories()
        await refreshFavorites()
    }

    /// 探测站点认证能力，并校验本地会话是否还有效
    func probeAuth() async {
        pluginReady = await AuthClient.shared.pluginAvailable()
        registrationOpen = pluginReady && await AuthClient.shared.registrationOpen()
        guard var s = Prefs.session else { return }
        if let refreshed = await AuthClient.shared.validate(s) {
            s = refreshed
            session = refreshed
            Prefs.session = refreshed
        } else {
            Prefs.clearSession()
            session = nil
        }
    }

    func login(username: String, password: String) async {
        guard !username.isEmpty, !password.isEmpty else {
            authError = "请填写用户名和密码"
            return
        }
        authBusy = true
        authError = nil
        authNotice = nil
        defer { authBusy = false }
        do {
            let s = try await AuthClient.shared.login(username: username, password: password)
            session = s
            authNotice = "登录成功，欢迎回来 \(s.name)"
        } catch {
            authError = readable(error, action: "登录")
        }
    }

    func register(username: String, email: String, password: String) async {
        if username.trimmingCharacters(in: .whitespaces).count < 3 {
            authError = "用户名至少 3 个字符"; return
        }
        if !email.contains("@") {
            authError = "邮箱格式不正确"; return
        }
        if password.count < 6 {
            authError = "密码至少 6 位"; return
        }
        authBusy = true
        authError = nil
        authNotice = nil
        defer { authBusy = false }
        do {
            let s = try await AuthClient.shared.register(
                username: username, email: email, password: password
            )
            session = s
            authNotice = "注册成功，已自动登录"
        } catch {
            authError = readable(error, action: "注册")
        }
    }

    func lostPassword(_ login: String) async {
        guard !login.isEmpty else {
            authError = "请填写用户名或邮箱"; return
        }
        authBusy = true
        authError = nil
        defer { authBusy = false }
        do {
            try await AuthClient.shared.lostPassword(login: login)
            authNotice = "重置邮件已发送，请到邮箱查收"
        } catch {
            authError = readable(error, action: "找回密码")
        }
    }

    func logout() async {
        if let s = session {
            await AuthClient.shared.logout(s)
        }
        Prefs.clearSession()
        session = nil
        authNotice = nil
    }

    func clearAuthMessage() {
        authError = nil
        authNotice = nil
    }

    private func readable(_ error: Error, action: String) -> String {
        if let e = error as? AuthError { return "\(action)失败：\(e.localizedDescription)" }
        if let e = error as? WPError {
            switch e {
            case .http(let code, let msg):
                switch code {
                case 401: return "\(action)失败：用户名或密码不正确"
                case 403: return "\(action)失败：服务器拒绝请求（403）"
                case 404: return "\(action)失败：接口不存在（404），请确认站点已启用 ZhuJiTown Auth 插件"
                case 409: return "\(action)失败：用户名或邮箱已被占用"
                case 429: return "尝试过于频繁，请稍后再试"
                default: return "\(action)失败：服务返回 \(code)\(msg.isEmpty ? "" : "：\(msg)")"
                }
            default: return "\(action)失败：\(e.localizedDescription)"
            }
        }
        return "\(action)失败：\(error.localizedDescription)"
    }

    func loadCategories(force: Bool = false) async {
        if !categories.isEmpty && !force { return }
        categoriesLoading = true
        defer { categoriesLoading = false }
        do {
            let list = try await WPClient.shared.categories()
            // 有文章的排前面，同数量按名称
            categories = list.sorted { ($0.count, $0.name) > ($1.count, $1.name) }
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: 收藏

    func isFavorite(_ id: Int) -> Bool { favoriteIDs.contains(id) }

    func toggleFavorite(_ post: Post) {
        let now = Prefs.toggleFavorite(post.id)
        favoriteIDs = Prefs.favorites
        if now {
            Cache.save(post: post)
        } else {
            favoritePosts.removeAll { $0.id == post.id }
        }
        Task { await refreshFavorites() }
    }

    func refreshFavorites() async {
        favoriteIDs = Prefs.favorites
        // 先补本地已缓存的正文，离线可用
        var offline: [Post] = favoriteIDs.compactMap { Cache.loadPost(id: $0) }
        let missing = favoriteIDs.filter { Cache.loadPost(id: $0) == nil }
        if !missing.isEmpty {
            do {
                let fetched = try await WPClient.shared.posts(ids: missing)
                for p in fetched { Cache.save(post: p) }
                offline.append(contentsOf: fetched)
            } catch {
                notice = "收藏内容同步失败：\(error.localizedDescription)"
            }
        }
        favoritePosts = offline.sorted { $0.date > $1.date }
    }

    func clearCache() {
        Cache.clear()
        Cache.prepare()
        Task { await refreshFavorites() }
    }
}
