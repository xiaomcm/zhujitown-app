import Foundation

// MARK: - WordPress 富文本字段

/// `title` / `content` / `excerpt` 在标准 WP 里是 `{ "rendered": "...", "protected": false }`，
/// 但部分插件/自定义路由会直接返回纯字符串，两种都兼容。
struct Rendered: Codable, Equatable {
    let rendered: String
    let protected: Bool

    init(rendered: String = "", protected: Bool = false) {
        self.rendered = rendered
        self.protected = protected
    }

    private enum Keys: String, CodingKey { case rendered, protected }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            self.rendered = raw
            self.protected = false
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        self.rendered = (try? c.decode(String.self, forKey: .rendered)) ?? ""
        self.protected = (try? c.decode(Bool.self, forKey: .protected)) ?? false
    }
}

extension Rendered {
    /// 去掉 HTML 标签后的纯文本
    var plainText: String {
        rendered
            .replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression,
                range: nil
            )
            .decodingHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 文章

struct Post: Codable, Identifiable, Equatable {
    let id: Int
    let date: String
    let modified: String
    let slug: String
    let link: String
    let status: String
    let title: Rendered
    let content: Rendered
    let excerpt: Rendered
    let featuredMedia: Int
    let categories: [Int]
    let tags: [Int]
    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case id, date, modified, slug, link, status
        case title, content, excerpt
        case featuredMedia = "featured_media"
        case categories, tags
        case embedded = "_embedded"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(.id)
        date = c.decodeString(.date)
        modified = c.decodeString(.modified)
        slug = c.decodeString(.slug)
        link = c.decodeString(.link)
        status = c.decodeString(.status, default: "publish")
        title = (try? c.decode(Rendered.self, forKey: .title)) ?? Rendered()
        content = (try? c.decode(Rendered.self, forKey: .content)) ?? Rendered()
        excerpt = (try? c.decode(Rendered.self, forKey: .excerpt)) ?? Rendered()
        featuredMedia = c.decodeInt(.featuredMedia)
        categories = c.decodeIntArray(.categories)
        tags = c.decodeIntArray(.tags)
        embedded = try? c.decode(Embedded.self, forKey: .embedded)
    }

    /// 列表没带 _embed 时的兜底构造（搜索结果、草稿箱等场景不一定带）
    init(
        id: Int,
        date: String = "",
        link: String = "",
        title: String,
        excerpt: String = "",
        content: String = "",
        status: String = "publish",
        categories: [Int] = [],
        featuredMedia: Int = 0,
        embedded: Embedded? = nil
    ) {
        self.id = id
        self.date = date
        self.link = link
        self.title = Rendered(rendered: title)
        self.excerpt = Rendered(rendered: excerpt)
        self.content = Rendered(rendered: content)
        self.status = status
        self.categories = categories
        self.featuredMedia = featuredMedia
        self.modified = date
        self.slug = ""
        self.tags = []
        self.embedded = embedded
    }

    var plainTitle: String { title.plainText }
    var plainExcerpt: String { excerpt.plainText }

    /// 封面图：优先中等尺寸，失败回退原图
    var coverURL: URL? {
        guard let m = embedded?.featuredMedia?.first else { return nil }
        let sizes = m.mediaDetails?.sizes
        let pick = sizes?["medium_large"] ?? sizes?["medium"] ?? sizes?["thumbnail"]
        if let u = pick?.sourceURL, !u.isEmpty, let url = URL(string: u) { return url }
        guard let orig = m.sourceURL, !orig.isEmpty else { return nil }
        return URL(string: orig)
    }

    /// 分类名（wp:term 第一组是 category）
    var categoryNames: [String] {
        (embedded?.terms?.first ?? nil)?
            .map(\.name)
            .filter { !$0.isEmpty } ?? []
    }

    var tagNames: [String] {
        guard let t = embedded?.terms, t.count > 1, let group = t[1] else { return [] }
        return group.map(\.name).filter { !$0.isEmpty }
    }

    var authorName: String { embedded?.author?.first?.name ?? "" }

    var primaryCategoryID: Int? { categories.first }

    var displayDate: String { Self.formatDate(date) }

    /// `2026-10-10T14:03:21` → `2026-10-10`
    static func formatDate(_ raw: String) -> String {
        guard raw.count >= 10 else { return raw }
        let s = String(raw.prefix(10))
        guard raw.count >= 16 else { return s }
        // 需要精确到分钟时改用下面这行
        let day = String(s.dropFirst(8))
        let month = String(s.dropFirst(5).prefix(2))
        let year = String(s.prefix(4))
        return "\(year)-\(month)-\(day)"
    }
}

// MARK: - 嵌入资源

struct Embedded: Codable, Equatable {
    let featuredMedia: [Media]?
    let terms: [[Term]?]?
    let author: [Author]?

    enum CodingKeys: String, CodingKey {
        case featuredMedia = "wp:featuredmedia"
        case terms = "wp:term"
        case author
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        featuredMedia = try? c.decode([Media].self, forKey: .featuredMedia)
        terms = try? c.decode([[Term]?].self, forKey: .terms)
        author = try? c.decode([Author].self, forKey: .author)
    }
}

struct Media: Codable, Equatable {
    let id: Int
    let sourceURL: String
    let altText: String
    let mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceURL = "source_url"
        case altText = "alt_text"
        case mediaDetails = "media_details"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(.id)
        sourceURL = c.decodeString(.sourceURL)
        altText = c.decodeString(.altText)
        mediaDetails = try? c.decode(MediaDetails.self, forKey: .mediaDetails)
    }
}

struct MediaDetails: Codable, Equatable {
    let width: Int
    let height: Int
    let sizes: [String: MediaSize]?

    enum CodingKeys: String, CodingKey { case width, height, sizes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = c.decodeInt(.width)
        height = c.decodeInt(.height)
        sizes = try? c.decode([String: MediaSize].self, forKey: .sizes)
    }
}

struct MediaSize: Codable, Equatable {
    let sourceURL: String
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey { case sourceURL = "source_url", width, height }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = c.decodeString(.sourceURL)
        width = c.decodeInt(.width)
        height = c.decodeInt(.height)
    }
}

struct Term: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let slug: String
    let taxonomy: String
    let count: Int

    enum CodingKeys: String, CodingKey { case id, name, slug, taxonomy, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(.id)
        name = c.decodeString(.name)
        slug = c.decodeString(.slug)
        taxonomy = c.decodeString(.taxonomy)
        count = c.decodeInt(.count)
    }
}

struct Author: Codable, Equatable {
    let id: Int
    let name: String
    let slug: String
    let avatarURLs: [String: String]?

    enum CodingKeys: String, CodingKey { case id, name, slug, avatarURLs = "avatar_urls" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(.id)
        name = c.decodeString(.name)
        slug = c.decodeString(.slug)
        avatarURLs = try? c.decode([String: String].self, forKey: .avatarURLs)
    }

    var avatarURL: URL? {
        guard let best = avatarURLs?["96"] ?? avatarURLs?["48"] ?? avatarURLs?["24"] else { return nil }
        return URL(string: best)
    }
}

struct Comment: Codable, Identifiable, Equatable {
    let id: Int
    let post: Int
    let authorName: String
    let date: String
    let link: String
    let content: Rendered
    let authorAvatarURLs: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, post, date, link, content
        case authorName = "author_name"
        case authorAvatarURLs = "author_avatar_urls"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(.id)
        post = c.decodeInt(.post)
        authorName = c.decodeString(.authorName)
        date = c.decodeString(.date)
        link = c.decodeString(.link)
        content = (try? c.decode(Rendered.self, forKey: .content)) ?? Rendered()
        authorAvatarURLs = try? c.decode([String: String].self, forKey: .authorAvatarURLs)
    }

    var avatarURL: URL? {
        guard let best = authorAvatarURLs?["96"] ?? authorAvatarURLs?["48"] ?? authorAvatarURLs?["24"] else { return nil }
        return URL(string: best)
    }
}

struct Category: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let slug: String
    let description: String
    let parent: Int
    let count: Int

    enum CodingKeys: String, CodingKey { case id, name, slug, description, parent, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeInt(.id)
        name = c.decodeString(.name)
        slug = c.decodeString(.slug)
        description = c.decodeString(.description)
        parent = c.decodeInt(.parent)
        count = c.decodeInt(.count)
    }
}

// MARK: - 解码小工具

extension KeyedDecodingContainer {
    func decodeInt(_ key: Key, default value: Int = 0) -> Int {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let s = try? decodeIfPresent(String.self, forKey: key), let i = Int(s) { return i }
        return value
    }

    func decodeString(_ key: Key, default value: String = "") -> String {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "true" : "false" }
        return value
    }

    func decodeIntArray(_ key: Key) -> [Int] {
        if let a = try? decodeIfPresent([Int].self, forKey: key) { return a }
        if let a = try? decodeIfPresent([String].self, forKey: key) { return a.compactMap(Int.init) }
        return []
    }
}

// MARK: - HTML 实体

extension String {
    /// 把常见 HTML 实体换回真实字符（含数字实体 &#123; / &#x1F600;）
    var decodingHTMLEntities: String {
        var out = self
        let pairs: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&#8217;", "’"),
            ("&#8220;", "“"), ("&#8221;", "”"), ("&#8230;", "…"), ("&hellip;", "…"),
            ("&ldquo;", "“"), ("&rdquo;", "”"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&middot;", "·"), ("&times;", "×"), ("&deg;", "°"), ("&yen;", "¥")
        ]
        for (from, to) in pairs { out = out.replacingOccurrences(of: from, with: to) }

        guard out.contains("&#") else {
            return out.replacingOccurrences(
                of: "&[a-zA-Z]+;", with: "", options: .regularExpression
            )
        }

        // 数字实体：&#x1F600; / &#128512;
        var result = ""
        var search = out.startIndex
        while let open = out.range(of: "&#", range: search..<out.endIndex) {
            let rest = out[open.lowerBound...]
            guard let close = rest.firstIndex(of: ";") else { break }
            let body = String(out[open.upperBound..<close])
            var scalar: Unicode.Scalar?
            if body.hasPrefix("x") || body.hasPrefix("X") {
                if let v = UInt32(body.dropFirst(), radix: 16) { scalar = Unicode.Scalar(v) }
            } else if let v = UInt32(body) {
                scalar = Unicode.Scalar(v)
            }
            result += out[search..<open.lowerBound]
            if let s = scalar { result += String(Character(s)) } else { result += "&#" + body + ";" }
            search = out.index(after: close)
        }
        result += out[search...]
        return result.replacingOccurrences(
            of: "&[a-zA-Z]+;", with: "", options: .regularExpression
        )
    }
}
