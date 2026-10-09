import Foundation

// MARK: - 轻量 DOM

/// 极简 HTML 节点：够用就好，只为把 WordPress 正文拆成可原生渲染的块，
/// 不引第三方解析库，避免 Mac 上多一次 SwiftPM 依赖拉取。
final class HNode {

    static let textNode = "#text"

    let name: String
    var text: String = ""
    var attrs: [String: String] = [:]
    var children: [HNode] = []
    private(set) weak var parent: HNode?

    init(name: String) {
        self.name = name.lowercased()
    }

    var isText: Bool { name == HNode.textNode }

    /// 标签名（小写）
    var tag: String { name }

    func append(_ child: HNode) {
        child.parent = self
        children.append(child)
    }

    func attr(_ key: String) -> String {
        attrs[key.lowercased()] ?? ""
    }

    var style: String { attr("style").lowercased() }
    var classNames: String { attr("class").lowercased() }

    var isCentered: Bool {
        style.contains("center") ||
        classNames.contains("center") ||
        attr("align").lowercased() == "center"
    }

    /// 递归文本（跳过 script / style 内容）
    var textContent: String {
        if isText { return text }
        if name == "script" || name == "style" { return "" }
        if name == "br" { return "\n" }
        var out = ""
        for c in children { out += c.textContent }
        return out
    }

    /// 深度优先遍历所有子节点（含自身）
    func descendants() -> [HNode] {
        var out: [HNode] = []
        func walk(_ n: HNode) {
            for c in n.children {
                out.append(c)
                walk(c)
            }
        }
        walk(self)
        return out
    }

    func descendants(tag: String) -> [HNode] {
        descendants().filter { $0.tag == tag }
    }

    func firstDescendant(tag: String) -> HNode? {
        descendants().first { $0.tag == tag }
    }
}

// MARK: - 解析

enum MiniHTML {

    /// 空元素：不需要闭合标签
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    /// 块级元素：遇到块级起始标签时自动关闭尚未闭合的 <p>
    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "details", "dialog",
        "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main",
        "menu", "nav", "ol", "p", "pre", "section", "summary", "table", "ul"
    ]

    /// 把 HTML 解析成一棵精简树（尽力而为：容错未闭合标签）
    static func parse(_ html: String) -> HNode {
        let root = HNode(name: "#root")
        var stack: [HNode] = [root]

        func close(named name: String) {
            guard !name.isEmpty else { return }
            var i = stack.count - 1
            while i > 0 {
                if stack[i].tag == name {
                    stack.removeSubrange(i..<stack.count)
                    return
                }
                i -= 1
            }
        }

        func push(_ tagName: String, attrs: [String: String]) {
            // 块级标签自动关闭悬空的 <p>
            if blockTags.contains(tagName), let top = stack.last, top.tag == "p" {
                stack.removeLast()
            }
            if tagName == "li", let top = stack.last, top.tag == "li" {
                stack.removeLast()
            }
            if (tagName == "td" || tagName == "th" || tagName == "tr"),
               let top = stack.last,
               top.tag == "td" || top.tag == "th" {
                stack.removeLast()
            }
            if tagName == "tr", let top = stack.last, top.tag == "tr" {
                stack.removeLast()
            }
            if tagName == "tbody" || tagName == "thead" || tagName == "tr",
               let top = stack.last, top.tag == "p" {
                stack.removeLast()
            }

            let node = HNode(name: tagName)
            node.attrs = attrs
            stack[stack.count - 1].append(node)
            if !voidTags.contains(tagName) {
                stack.append(node)
            }
        }

        let s = html
        var idx = s.startIndex

        while idx < s.endIndex {
            let ch = s[idx]
            guard ch == "<" else {
                // 文本节点：一直读到下一个 '<'
                let rest = s[idx...]
                let nextTag = rest.firstIndex(of: "<") ?? s.endIndex
                let raw = String(s[idx..<nextTag])
                if !raw.isEmpty {
                    let t = HNode(name: HNode.textNode)
                    t.text = raw
                    stack[stack.count - 1].append(t)
                }
                idx = nextTag
                continue
            }

            let next = s.index(after: idx)
            guard next < s.endIndex else { break }

            let c = s[next]

            // <!-- 注释 --> / <!DOCTYPE>
            if c == "!" {
                let rest = s[next...]
                if let end = rest.range(of: "-->") {
                    idx = end.upperBound
                } else if let end = rest.firstIndex(of: ">") {
                    idx = s.index(after: end)
                } else {
                    idx = s.endIndex
                }
                continue
            }

            // <? ... ?>
            if c == "?" {
                let rest = s[next...]
                if let end = rest.range(of: "?>") {
                    idx = end.upperBound
                } else {
                    idx = s.endIndex
                }
                continue
            }

            // </tag>
            if c == "/" {
                let body = s[s.index(after: next)...]
                let end = endOfTag(body)
                let name = tagName(from: String(s[s.index(after: next)..<end]))
                close(named: name)
                idx = s.index(after: end)
                continue
            }

            // <tag ...>
            if c.isLetter {
                let body = s[next...]
                let end = endOfTag(body)
                let raw = String(s[next..<end])
                let (tagNameStr, attrs) = splitTag(raw)
                let name = tagName(from: tagNameStr)
                if !name.isEmpty {
                    push(name, attrs: attrs)
                }
                idx = s.index(after: end)
                continue
            }

            // 其它情况（如 "< 2"）当文本处理
            let t = HNode(name: HNode.textNode)
            t.text = String(ch)
            stack[stack.count - 1].append(t)
            idx = next
        }

        return root
    }

    /// 找到标签的 '>'，忽略引号内的 '>'
    private static func endOfTag(_ body: Substring) -> String.Index {
        var quote: Character? = nil
        var i = body.startIndex
        while i < body.endIndex {
            let ch = body[i]
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == ">" {
                return i
            }
            i = body.index(after: i)
        }
        return body.endIndex
    }

    private static func tagName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let first = trimmed.first, first.isLetter else { return "" }
        var out = ""
        for ch in trimmed {
            if ch.isLetter || ch.isNumber || ch == "-" { out.append(ch) } else { break }
        }
        return out
    }

    /// 拆分 `<a href="x" class=y>` → ("a", ["href":"x","class":"y"])
    private static func splitTag(_ raw: String) -> (String, [String: String]) {
        var attrs: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*(?:=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+)))?",
            options: []
        ) else { return (raw, attrs) }

        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var nameFound = false
        var name = ""
        for m in regex.matches(in: raw, options: [], range: nsRange) {
            guard let keyRange = Range(m.range(at: 1), in: raw) else { continue }
            let key = String(raw[keyRange]).lowercased()
            var value = ""
            for g in 2...4 {
                if m.range(at: g).location != NSNotFound,
                   let r = Range(m.range(at: g), in: raw) {
                    value = String(raw[r])
                    break
                }
            }
            if !nameFound {
                name = key
                nameFound = true
            } else {
                attrs[key] = value.decodingHTMLEntities
            }
        }
        return (name, attrs)
    }
}
