import Foundation

// MARK: - 偏好设置

enum PrefKey: String {
    case siteURL = "site_url"
    case favorites = "favorites"
    case fontSize = "font_size"
    case imageQuality = "image_quality"
    case appearance = "appearance"
    case history = "history"
    /// 登录会话（Session JSON）
    case session = "auth_session"
}

/// 统一的 UserDefaults 入口（带默认值注册）
enum Prefs {
    static let suite = UserDefaults.standard

    static func registerDefaults() {
        suite.register(defaults: [
            PrefKey.siteURL.rawValue: AppConfig.siteURL,
            PrefKey.fontSize.rawValue: 17.0,
            PrefKey.imageQuality.rawValue: "auto",
            PrefKey.appearance.rawValue: "auto"
        ])
    }

    // 站点
    static var siteURL: String {
        get { (suite.string(forKey: PrefKey.siteURL.rawValue) ?? AppConfig.siteURL) }
        set { suite.set(newValue, forKey: PrefKey.siteURL.rawValue) }
    }

    // MARK: 账号会话

    static var session: Session? {
        get {
            guard let data = suite.data(forKey: PrefKey.session.rawValue) else { return nil }
            return try? JSONDecoder().decode(Session.self, from: data)
        }
        set {
            guard let s = newValue,
                  let data = try? JSONEncoder().encode(s) else {
                suite.removeObject(forKey: PrefKey.session.rawValue)
                return
            }
            suite.set(data, forKey: PrefKey.session.rawValue)
        }
    }

    static func clearSession() {
        suite.removeObject(forKey: PrefKey.session.rawValue)
    }

    /// 供文章接口使用的 Authorization 头值（未登录为 nil）
    static var authorizationValue: String? { session?.authorizationValue }

    // 阅读设置
    static var fontSize: Double {
        get {
            let v = suite.double(forKey: PrefKey.fontSize.rawValue)
            return v <= 0 ? 17.0 : v
        }
        set { suite.set(newValue, forKey: PrefKey.fontSize.rawValue) }
    }

    enum ImageQuality: String, CaseIterable, Identifiable {
        case always = "always"      // 始终加载
        case wifi = "wifi"          // 仅 Wi-Fi
        case never = "never"        // 无图
        var id: String { rawValue }
        var label: String {
            switch self {
            case .always: return "始终加载"
            case .wifi: return "仅 Wi-Fi 下加载"
            case .never: return "无图（省流量）"
            }
        }
    }

    static var imageQuality: ImageQuality {
        get {
            ImageQuality(
                rawValue: suite.string(forKey: PrefKey.imageQuality.rawValue) ?? "always"
            ) ?? .always
        }
        set { suite.set(newValue.rawValue, forKey: PrefKey.imageQuality.rawValue) }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case auto, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }
    }

    static var appearance: Appearance {
        get {
            Appearance(rawValue: suite.string(forKey: PrefKey.appearance.rawValue) ?? "auto") ?? .auto
        }
        set { suite.set(newValue.rawValue, forKey: PrefKey.appearance.rawValue) }
    }

    // 收藏
    static var favorites: Set<Int> {
        get {
            let a = suite.array(forKey: PrefKey.favorites.rawValue) as? [Int] ?? []
            return Set(a)
        }
        set { suite.set(Array(newValue), forKey: PrefKey.favorites.rawValue) }
    }

    static func toggleFavorite(_ id: Int) -> Bool {
        var f = favorites
        if f.contains(id) { f.remove(id) } else { f.insert(id) }
        favorites = f
        return f.contains(id)
    }

    static func isFavorite(_ id: Int) -> Bool { favorites.contains(id) }

    // 浏览历史（最近 100 条）
    static var history: [Int] {
        get { suite.array(forKey: PrefKey.history.rawValue) as? [Int] ?? [] }
        set { suite.set(Array(newValue.prefix(100)), forKey: PrefKey.history.rawValue) }
    }

    static func recordHistory(_ id: Int) {
        var h = history.filter { $0 != id }
        h.insert(id, at: 0)
        history = h
    }
}

// MARK: - 离线缓存

/// 文章正文离线缓存 + 图片磁盘缓存目录
enum Cache {
    private static var base: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ZhuJiTown", isDirectory: true)
    }

    private static var postDir: URL { base.appendingPathComponent("posts", isDirectory: true) }

    static func prepare() {
        try? FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)
    }

    static func save(post: Post) {
        prepare()
        guard let data = try? JSONEncoder().encode(post) else { return }
        let file = postDir.appendingPathComponent("\(post.id).json")
        try? data.write(to: file, options: .atomic)
    }

    static func loadPost(id: Int) -> Post? {
        let file = postDir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Post.self, from: data)
    }

    static func removePost(id: Int) {
        let file = postDir.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: file)
    }

    static func postCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(at: postDir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    /// 收藏但未缓存的文章：下载完缓存后再清理无用正文
    static func clear() {
        try? FileManager.default.removeItem(at: base)
    }

    static var sizeDescription: String {
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return "0 KB" }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let v = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(v)
        }
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        return f.string(fromByteCount: total)
    }
}
