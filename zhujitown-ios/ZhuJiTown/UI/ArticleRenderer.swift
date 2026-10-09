import SwiftUI

// MARK: - 正文渲染入口

struct ArticleView: View {
    let blocks: [Block]
    var fontSize: CGFloat = 17
    var onLinkTap: (URL) -> Void
    var onImageTap: (String, String) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { _, block in
                BlockView(
                    block: block,
                    fontSize: fontSize,
                    onLinkTap: onLinkTap,
                    onImageTap: onImageTap
                )
            }
        }
    }
}

// MARK: - 单块渲染

struct BlockView: View {
    let block: Block
    var fontSize: CGFloat
    var onLinkTap: (URL) -> Void
    var onImageTap: (String, String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch block {
        case .heading(let level, let text, let anchor):
            heading(level: level, text: text, anchor: anchor)

        case .paragraph(let spans, let centered):
            RichText(
                attributed: InlineRenderer.render(
                    spans,
                    fontSize: fontSize,
                    color: UIColor.label,
                    alignment: centered ? .center : .natural
                ),
                lineSpacing: 7,
                alignment: centered ? .center : .left,
                onLink: onLinkTap
            )
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)

        case .image(let url, let alt, let caption):
            ArticleImageView(url: url, alt: alt, caption: caption) {
                onImageTap(url, alt)
            }

        case .table(let header, let rows):
            ArticleTable(header: header, rows: rows, fontSize: max(fontSize - 2, 12), onLinkTap: onLinkTap)

        case .list(let ordered, let items):
            ArticleList(ordered: ordered, items: items, fontSize: fontSize, onLinkTap: onLinkTap)

        case .quote(let spans):
            quote(spans)

        case .code(let text):
            codeBlock(text)

        case .divider:
            Divider().padding(.vertical, 6)
        }
    }

    // MARK: 标题

    private func heading(level: Int, text: String, anchor: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 4, height: headingHeight(level))
            Text(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, level <= 2 ? 12 : 8)
        .id(anchor)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 7
        case 2: return fontSize + 5
        case 3: return fontSize + 3
        default: return fontSize + 1
        }
    }

    private func headingHeight(_ level: Int) -> CGFloat {
        CGFloat(headingSize(level) * 1.15)
    }

    // MARK: 引用

    private func quote(_ spans: [Inline]) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 3)
            RichText(
                attributed: InlineRenderer.render(
                    spans,
                    fontSize: max(fontSize - 1, 12),
                    color: UIColor.secondaryLabel,
                    alignment: .natural
                ),
                lineSpacing: 6,
                onLink: onLinkTap
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    // MARK: 代码

    private func codeBlock(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: max(fontSize - 3, 11), design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

// MARK: - 列表

private struct ArticleList: View {
    let ordered: Bool
    let items: [[Inline]]
    var fontSize: CGFloat
    var onLinkTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, spans in
                HStack(alignment: .top, spacing: 8) {
                    Group {
                        if ordered {
                            Text("\(index + 1).")
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5, height: 5)
                                .padding(.top, fontSize * 0.55)
                        }
                    }
                    .frame(width: 22, alignment: .leading)

                    RichText(
                        attributed: InlineRenderer.render(spans, fontSize: fontSize),
                        lineSpacing: 6,
                        onLink: onLinkTap
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - 表格

/// 原生表格：真实单元格 + 横向滚动 + 保留站点里的居中设置 + 单元格内链接可点
private struct ArticleTable: View {
    let header: [Block.Cell]?
    let rows: [[Block.Cell]]
    var fontSize: CGFloat
    var onLinkTap: (URL) -> Void

    private var columnCount: Int {
        max(header?.count ?? 0, rows.map(\.count).max() ?? 0, 1)
    }

    private var columnWidth: CGFloat {
        let available = max(UIScreen.main.bounds.width - 40, 240)
        let raw = available / CGFloat(min(columnCount, 4))
        return max(raw, 96)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if let header {
                    rowView(header, header: true)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                    rowView(cells, header: false)
                }
            }
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func rowView(_ cells: [Block.Cell], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                cellView(cell)
                    .frame(width: columnWidth, alignment: cell.centered ? .center : .leading)
                if index < cells.count - 1 {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(width: 1)
                }
            }
        }
        .background(header ? Color(uiColor: .secondarySystemBackground) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
        }
    }

    private func cellView(_ cell: Block.Cell) -> some View {
        RichText(
            attributed: InlineRenderer.render(
                cell.spans,
                fontSize: fontSize,
                color: UIColor.label,
                alignment: cell.centered ? .center : .natural
            ),
            lineSpacing: 4,
            alignment: cell.centered ? .center : .left,
            onLink: onLinkTap
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - 正文图片

/// 按真实宽高比撑开的图片 + 图注 + 点击全屏预览
struct ArticleImageView: View {
    let url: String
    let alt: String
    let caption: String?
    let onTap: () -> Void

    @StateObject private var loader = ImageLoader()
    @State private var forceLoad = false

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onTap) {
                imageBody
            }
            .buttonStyle(.plain)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var imageBody: some View {
        if blocked {
            placeholder(text: "无图模式", systemImage: "photo.slash")
        } else if let img = loader.image {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(img.size.width / max(img.size.height, 1), contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                        .foregroundStyle(.white)
                }
        } else if loader.failed {
            placeholder(text: alt.isEmpty ? "图片加载失败" : alt, systemImage: "exclamationmark.triangle")
        } else {
            placeholder(text: alt.isEmpty ? "加载中" : alt, systemImage: "photo")
                .overlay {
                    if Prefs.imageQuality != .never { ProgressView() }
                }
        }
    }

    private var blocked: Bool {
        guard !forceLoad else { return false }
        switch Prefs.imageQuality {
        case .never: return true
        case .wifi: return NetworkMonitor.shared.isExpensive
        case .always: return false
        }
    }

    private func placeholder(text: String, systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .frame(height: 160)
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(text)
                    .font(.caption)
                    .lineLimit(2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .task(id: url) {
            guard !blocked else { return }
            loader.cancel()
            if let u = URL(string: url) { loader.load(u) }
        }
    }
}
