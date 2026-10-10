import Foundation

/// 分页响应（从 `X-WP-TotalPages` / `X-WP-Total` 头读取总数）
struct PageResult<T: Decodable> {
    let items: [T]
    let totalPages: Int
    let total: Int
}

enum WPError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "地址无效：\(s)"
        case .http(let code, let msg): return "服务返回 \(code)\(msg.isEmpty ? "" : "：\(msg)")"
        case .empty: return "没有内容"
        }
    }
}

/// WordPress REST API 客户端。站点响应偏慢且偶发 502，这里做「长超时 + 指数退避重试」。
final class WPClient {

    static let shared = WPClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = true
        cfg.httpAdditionalHeaders = [
            "User-Agent": AppConfig.userAgent,
            "Accept": "application/json"
        ]
        cfg.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: nil
        )
        self.session = URLSession(configuration: cfg)
        self.decoder = JSONDecoder()
    }

    // MARK: - 端点

    /// 文章列表（支持分类 / 关键词 / 草稿）
    func posts(
        page: Int = 1,
        perPage: Int = 20,
        category: Int? = nil,
        search: String? = nil,
        status: String? = nil,
        orderBy: String = "date",
        order: String = "desc"
    ) async throws -> PageResult<Post> {
        var items: [URLQueryItem] = [
            .init(name: "page", value: "\(page)"),
            .init(name: "per_page", value: "\(perPage)"),
            .init(name: "_embed", value: "true"),
            .init(name: "orderby", value: orderBy),
            .init(name: "order", value: order)
        ]
        if let c = category { items.append(.init(name: "categories", value: "\(c)")) }
        if let s = search, !s.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(.init(name: "search", value: s))
        }
        if let st = status, !st.isEmpty { items.append(.init(name: "status", value: st)) }
        return try await fetchPaged("posts", query: items)
    }

    /// 单篇文章
    func post(id: Int, refresh: Bool = false) async throws -> Post {
        if !refresh, let cached = Cache.loadPost(id: id) { return cached }
        let p: Post = try await fetch("posts/\(id)", query: [.init(name: "_embed", value: "true")])
        Cache.save(post: p)
        return p
    }

    /// 通过 slug 找文章（URL Scheme / Universal Link 用）
    func post(slug: String) async throws -> Post? {
        let list: [Post] = try await fetch("posts", query: [
            .init(name: "slug", value: slug),
            .init(name: "per_page", value: "1"),
            .init(name: "_embed", value: "true")
        ])
        return list.first
    }

    /// 按文章 ID 批量取（收藏夹离线数据补全）
    func posts(ids: [Int]) async throws -> [Post] {
        guard !ids.isEmpty else { return [] }
        let idList = ids.map(String.init).joined(separator: ",")
        let items = [
            URLQueryItem(name: "include", value: idList),
            URLQueryItem(name: "per_page", value: "\(ids.count)"),
            URLQueryItem(name: "_embed", value: "true")
        ]
        let r: PageResult<Post> = try await fetchPaged("posts", query: items)
        return r.items
    }

    /// 分类列表
    func categories(perPage: Int = 100) async throws -> [Category] {
        let list: [Category] = try await fetch("categories", query: [
            .init(name: "per_page", value: "\(perPage)"),
            .init(name: "orderby", value: "count"),
            .init(name: "order", value: "desc"),
            .init(name: "hide_empty", value: "true")
        ])
        return list
    }

    /// 同分类相关阅读
    func related(category: Int?, exclude: Int, perPage: Int = 6) async throws -> [Post] {
        var q: [URLQueryItem] = [
            .init(name: "exclude", value: "\(exclude)"),
            .init(name: "per_page", value: "\(perPage)"),
            .init(name: "_embed", value: "true")
        ]
        if let c = category { q.append(.init(name: "categories", value: "\(c)")) }
        let list: [Post] = try await fetch("posts", query: q)
        return list
    }

    /// 上 / 下一篇（before=更早，after=更晚）
    func neighbor(post: Post, direction: NeighborDirection) async throws -> Post? {
        var q: [URLQueryItem] = [
            .init(name: "per_page", value: "1"),
            .init(name: "orderby", value: "date")
        ]
        switch direction {
        case .previous:
            q.append(.init(name: "before", value: post.date))
            q.append(.init(name: "order", value: "desc"))
        case .next:
            q.append(.init(name: "after", value: post.date))
            q.append(.init(name: "order", value: "asc"))
        }
        let list: [Post] = try await fetch("posts", query: q)
        return list.first
    }

    enum NeighborDirection { case previous, next }

    /// 评论
    func comments(postID: Int, perPage: Int = 20) async throws -> [Comment] {
        let list: [Comment] = try await fetch("comments", query: [
            .init(name: "post", value: "\(postID)"),
            .init(name: "per_page", value: "\(perPage)"),
            .init(name: "orderby", value: "date"),
            .init(name: "order", value: "asc"),
            .init(name: "status", value: "approve")
        ])
        return list
    }

    /// 按作者取文章（个人中心「我的文章」/「草稿箱」）
    func postsByAuthor(
        author: Int,
        page: Int = 1,
        perPage: Int = 15,
        status: String? = nil
    ) async throws -> PageResult<Post> {
        var items: [URLQueryItem] = [
            .init(name: "author", value: "\(author)"),
            .init(name: "page", value: "\(page)"),
            .init(name: "per_page", value: "\(perPage)"),
            .init(name: "_embed", value: "true"),
            .init(name: "orderby", value: "date"),
            .init(name: "order", value: "desc")
        ]
        if let st = status, !st.isEmpty { items.append(.init(name: "status", value: st)) }
        return try await fetchPaged("posts", query: items)
    }

    /// 按作者取评论（个人中心「我的评论」）
    func commentsByAuthor(
        author: Int,
        page: Int = 1,
        perPage: Int = 15,
        status: String = "approve"
    ) async throws -> PageResult<Comment> {
        let items: [URLQueryItem] = [
            .init(name: "author", value: "\(author)"),
            .init(name: "page", value: "\(page)"),
            .init(name: "per_page", value: "\(perPage)"),
            .init(name: "orderby", value: "date"),
            .init(name: "order", value: "desc"),
            .init(name: "status", value: status)
        ]
        return try await fetchPaged("comments", query: items)
    }

    /// 媒体详情（封面图取大图时用）
    func media(id: Int) async throws -> Media {
        let m: Media = try await fetch("media/\(id)", query: [])
        return m
    }

    // MARK: - 底层

    private func apiRoot() throws -> URL {
        var s = Prefs.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { throw WPError.badURL("站点地址为空") }
        s += "/wp-json/wp/v2/"
        guard let u = URL(string: s) else { throw WPError.badURL(s) }
        return u
    }

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        let url = try apiRoot().appendingPathComponent(path)
        var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comp?.queryItems = query.isEmpty ? nil : query
        guard let finalURL = comp?.url else { throw WPError.badURL(path) }

        var req = URLRequest(url: finalURL, cachePolicy: .reloadRevalidatingCacheData)
        if let auth = Prefs.authorizationValue {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func fetch<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        let req = try makeRequest(path: path, query: query)
        let (data, response) = try await sendWithRetry(req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160) ?? ""
            throw WPError.http(http.statusCode, String(msg))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // 某些缓存插件会包一层 HTML，给出更明确的提示
            let head = String(data: data.prefix(80), encoding: .utf8) ?? ""
            if head.contains("<") {
                throw WPError.http(200, "返回了 HTML 而非 JSON，可能是缓存插件拦截了 /wp-json/")
            }
            throw error
        }
    }

    private func fetchPaged<T: Decodable>(
        _ path: String,
        query: [URLQueryItem]
    ) async throws -> PageResult<T> {
        let req = try makeRequest(path: path, query: query)
        let (data, response) = try await sendWithRetry(req)
        guard let http = response as? HTTPURLResponse else {
            throw WPError.empty
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160) ?? ""
            throw WPError.http(http.statusCode, String(msg))
        }
        let items = (try? decoder.decode([T].self, from: data)) ?? []
        let totalPages = Int(http.value(forHTTPHeaderField: "X-WP-TotalPages") ?? "") ?? 1
        let total = Int(http.value(forHTTPHeaderField: "X-WP-Total") ?? "") ?? items.count
        return PageResult(items: items, totalPages: max(totalPages, 1), total: total)
    }

    /// 三次重试 + 退避（0.6s / 1.2s / 2.4s）
    private func sendWithRetry(_ request: URLRequest, attempts: Int = 3) async throws -> (Data, URLResponse) {
        var lastError: Error = URLError(.cannotConnectToHost)
        for attempt in 0..<attempts {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    let nanos = UInt64(pow(2.0, Double(attempt)) * 600_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                }
            }
        }
        throw lastError
    }
}
