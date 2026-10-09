import Foundation

// MARK: - 正文模型

/// 行内片段：文字 / 链接
enum Inline {
    case text(String, bold: Bool = false, underline: Bool = false, italic: Bool = false)
    case link(text: String, url: String, bold: Bool = false, underline: Bool = false)
}

/// 正文块：全部用 SwiftUI 原生组件渲染，不走 WebView
enum Block: Identifiable {
    case heading(level: Int, text: String, anchor: String)
    case paragraph([Inline], centered: Bool)
    case image(url: String, alt: String, caption: String?)
    case table(header: [Cell]?, rows: [[Cell]])
    case list(ordered: Bool, items: [[Inline]])
    case quote([Inline])
    case code(String)
    case divider

    var id: String {
        switch self {
        case .heading(let l, let t, let a): return "h-\(l)-\(a)-\(t.hashValue)"
        case .paragraph(let s, _): return "p-\(s.count)-\(UUID().uuidString.prefix(6))"
        case .image(let u, _, _): return "img-\(u)"
        case .table(let h, let r): return "t-\(h?.count ?? 0)-\(r.count)-\(UUID().uuidString.prefix(6))"
        case .list(_, let items): return "l-\(items.count)-\(UUID().uuidString.prefix(6))"
        case .quote(let s): return "q-\(s.count)-\(UUID().uuidString.prefix(6))"
        case .code(let t): return "code-\(t.count)-\(UUID().uuidString.prefix(6))"
        case .divider: return "hr-\(UUID().uuidString.prefix(6))"
        }
    }

    struct Cell: Identifiable {
        let id = UUID()
        let spans: [Inline]
        let centered: Bool
    }
}

extension Block {
    /// 目录项（h2 / h3）
    var headingInfo: (level: Int, text: String, anchor: String)? {
        if case .heading(let level, let text, let anchor) = self { return (level, text, anchor) }
        return nil
    }
}

// MARK: - 解析

enum ArticleParser {

    /// HTML → 原生块
    static func parse(html: String, baseURL: URL?) -> [Block] {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let root = MiniHTML.parse(html)
        var out: [Block] = []
        walk(node: root, out: &out, baseURL: baseURL, depth: 0)
        return out
    }

    private static func walk(node: HNode, out: inout [Block], baseURL: URL?, depth: Int) {
        guard depth <= 6 else { return }
        for child in node.children {
            switch child.tag {
            case HNode.textNode:
                let t = child.text
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    out.append(.paragraph([.text(t)], centered: false))
                }

            case "script", "style", "noscript", "iframe", "form", "button", "input", "svg":
                continue

            case "h1", "h2", "h3", "h4", "h5", "h6":
                let text = child.textContent.collapsedWhitespace
                guard !text.isEmpty else { continue }
                let level = Int(child.tag.dropFirst()) ?? 2
                let anchor = child.attr("id").isEmpty ? "blk-\(out.count)" : child.attr("id")
                out.append(.heading(level: level, text: text, anchor: anchor))

            case "p":
                handleParagraph(child, out: &out, baseURL: baseURL)

            case "figure":
                handleFigure(child, out: &out, baseURL: baseURL)

            case "img":
                addImage(child, caption: nil, out: &out)

            case "table":
                out.append(parseTable(child, baseURL: baseURL))

            case "ul", "ol":
                let items = child.children
                    .filter { $0.tag == "li" }
                    .map { inline(in: $0, baseURL: baseURL) }
                    .filter { !$0.isEmpty }
                if !items.isEmpty {
                    out.append(.list(ordered: child.tag == "ol", items: items))
                }

            case "blockquote":
                var spans: [Inline] = []
                let ps = child.children.filter { $0.tag == "p" }
                if ps.isEmpty {
                    spans = inline(in: child, baseURL: baseURL)
                } else {
                    for p in ps { spans.append(contentsOf: inline(in: p, baseURL: baseURL)) }
                }
                if !spans.isEmpty { out.append(.quote(spans)) }

            case "pre":
                let code = child.textContent.collapsedWhitespace
                if !code.isEmpty { out.append(.code(code)) }

            case "hr":
                out.append(.divider)

            default:
                // div / section / figure 包裹容器：继续往下钻
                walk(node: child, out: &out, baseURL: baseURL, depth: depth + 1)
            }
        }
    }

    // MARK: 段落

    private static func handleParagraph(_ p: HNode, out: inout [Block], baseURL: URL?) {
        for img in p.descendants(tag: "img") {
            addImage(img, caption: nil, out: &out)
        }
        let spans = inline(in: p, baseURL: baseURL)
        if spans.isEmpty { return }
        out.append(.paragraph(spans, centered: p.isCentered))
    }

    private static func handleFigure(_ figure: HNode, out: inout [Block], baseURL: URL?) {
        let captionNode = figure.firstDescendant(tag: "figcaption")
        let caption = captionNode?.textContent.collapsedWhitespace
        let imgs = figure.descendants(tag: "img")
        if imgs.isEmpty {
            walk(node: figure, out: &out, baseURL: baseURL, depth: 2)
            return
        }
        for img in imgs {
            addImage(img, caption: caption, out: &out)
        }
    }

    private static func addImage(_ img: HNode, caption: String?, out: inout [Block]) {
        let raw = [
            img.attr("src"),
            img.attr("data-src"),
            img.attr("data-original"),
            img.attr("data-lazy-src"),
            img.attr("data-ezsrc")
        ].first { !$0.isEmpty } ?? ""
        guard !raw.isEmpty else { return }
        let url = resolve(raw, against: nil)
        let alt = img.attr("alt").ifEmpty(caption ?? "")
        let cap = (caption?.isEmpty ?? true) ? nil : caption
        out.append(.image(url: url, alt: alt, caption: cap))
    }

    // MARK: 表格

    private static func parseTable(_ table: HNode, baseURL: URL?) -> Block {
        var header: [Block.Cell] = []
        var rows: [[Block.Cell]] = []

        func cells(of tr: HNode) -> [Block.Cell] {
            tr.children
                .filter { $0.tag == "td" || $0.tag == "th" }
                .map { cell in
                    Block.Cell(spans: inline(in: cell, baseURL: baseURL), centered: cell.isCentered)
                }
        }

        func collect(_ node: HNode) {
            for child in node.children {
                switch child.tag {
                case "tr":
                    let cs = cells(of: child)
                    guard !cs.isEmpty else { continue }
                    if child.children.contains(where: { $0.tag == "th" }), rows.isEmpty {
                        header.append(contentsOf: cs)
                    } else {
                        rows.append(cs)
                    }
                case "thead", "tbody", "tfoot":
                    collect(child)
                default:
                    if !child.children.isEmpty { collect(child) }
                }
            }
        }

        collect(table)

        // 没有 th 时把首行当表头
        if header.isEmpty && !rows.isEmpty {
            header = rows.removeFirst()
        }
        return .table(header: header.isEmpty ? nil : header, rows: rows)
    }

    // MARK: 行内

    private static func inline(in node: HNode, baseURL: URL?) -> [Inline] {
        var out: [Inline] = []

        func visit(_ n: HNode, bold: Bool, underline: Bool, italic: Bool) {
            for child in n.children {
                switch child.tag {
                case HNode.textNode:
                    let t = child.text.replacingOccurrences(of: "\u{00A0}", with: " ")
                    if !t.isEmpty { out.append(.text(t, bold: bold, underline: underline, italic: italic)) }
                case "br":
                    out.append(.text("\n", bold: bold, underline: underline, italic: italic))
                case "a":
                    let href = child.attr("href")
                    let abs = resolve(href, against: baseURL)
                    let text = child.textContent.collapsedWhitespace
                    if !text.isEmpty && !abs.isEmpty {
                        out.append(.link(text: text, url: abs, bold: bold, underline: underline))
                    } else if !text.isEmpty {
                        out.append(.text(text, bold: bold, underline: underline, italic: italic))
                    }
                case "img", "script", "style", "iframe", "noscript", "svg":
                    // 这里的图片已由上层作为独立块抽出
                    break
                case "strong", "b":
                    visit(child, bold: true, underline: underline, italic: italic)
                case "u", "ins":
                    visit(child, bold: bold, underline: true, italic: italic)
                case "em", "i":
                    visit(child, bold: bold, underline: underline, italic: true)
                default:
                    visit(child, bold: bold, underline: underline, italic: italic)
                }
            }
        }

        visit(node, bold: false, underline: false, italic: false)
        return mergedClean(out)
    }

    /// 去掉纯空白片段、合并无意义换行
    private static func mergedClean(_ spans: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for s in spans {
            switch s {
            case .text(let v, let b, let u, let i):
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty && !v.contains("\n") { continue }
                if trimmed.isEmpty { continue }
                out.append(.text(trimmed, bold: b, underline: u, italic: i))
            case .link(let text, let url, let b, let u):
                if text.isEmpty || url.isEmpty { continue }
                out.append(.link(text: text, url: url, bold: b, underline: u))
            }
        }
        return out
    }

    // MARK: 工具

    /// 相对路径转绝对 URL
    static func resolve(_ href: String, against base: URL?) -> String {
        let raw = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("#") || raw.lowercased().hasPrefix("javascript:") { return "" }
        if raw.hasPrefix("mailto:") || raw.hasPrefix("tel:") { return raw }
        if raw.hasPrefix("//") { return "https:" + raw }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        guard let b = base else {
            return raw.hasPrefix("/") ? "https://" + AppConfig.siteURL.hostOrSelf + raw : ""
        }
        return URL(string: raw, relativeTo: b)?.absoluteString ?? raw
    }

    /// 判断链接是否指向本站文章页
    static func isInternalArticle(_ url: String) -> Bool {
        guard let u = URL(string: url), let host = u.host else { return false }
        return AppConfig.siteURL.contains(host)
    }

    /// 从链接里抽出文章 ID：支持 `/1234.html`、`?p=1234`、`?page_id=1234`、`/post/1234`
    static func postID(from url: URL) -> Int? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }

        for key in ["p", "page_id", "post_id", "id"] {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value,
               let id = Int(value) {
                return id
            }
        }

        let parts = components.path.components(separatedBy: "/")
        if let last = parts.last(where: { !$0.isEmpty }) {
            let base = last.replacingOccurrences(of: ".html", with: "")
            if let id = Int(base) { return id }
        }
        // zhujitown://post/1234
        if components.host == "post",
           let second = parts.dropFirst().first,
           let id = Int(second) {
            return id
        }
        // 形如 /2026/10/09/slug-title-1234 的日期归档，尾部数字不一定可靠，忽略
        return nil
    }
}

// MARK: - String 辅助

extension String {
    /// 折叠连续空白，保持可读性
    var collapsedWhitespace: String {
        var out = self
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .decodingHTMLEntities
        while let r = out.range(of: "\\s{2,}", options: .regularExpression) {
            out = out.replacingCharacters(in: r, with: " ")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }

    var hostOrSelf: String {
        guard let u = URL(string: self), let h = u.host else { return self }
        return h
    }
}
