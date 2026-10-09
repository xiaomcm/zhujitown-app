import SwiftUI

// MARK: - 阅读进度

private struct ScrollMetric: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}

private struct DetailScrollKey: PreferenceKey {
    static var defaultValue: ScrollMetric = ScrollMetric(offset: 0, contentHeight: 0, viewportHeight: 0)
    static func reduce(value: inout ScrollMetric, nextValue: () -> ScrollMetric) {
        value = nextValue()
    }
}

// MARK: - 详情页

struct DetailView: View {

    let post: Post

    @EnvironmentObject private var app: AppModel
    @Environment(\.navPath) private var navPath
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PrefKey.fontSize.rawValue) private var fontSizeRaw: Double = 17

    @State private var blocks: [Block] = []
    @State private var related: [Post] = []
    @State private var previousPost: Post?
    @State private var nextPost: Post?
    @State private var comments: [Comment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showTOC = false
    @State private var viewerURLs: [String] = []
    @State private var viewerIndex = 0
    @State private var safari: IdentifiableURL?

    private var fontSize: CGFloat { CGFloat(fontSizeRaw) }

    private var headings: [(level: Int, text: String, anchor: String)] {
        blocks.compactMap { $0.headingInfo }
            .filter { $0.level <= 3 }
    }

    private var imageURLs: [String] {
        blocks.compactMap {
            if case .image(let url, _, _) = $0 { return url }
            return nil
        }
    }

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        bodyContent
                    }
                    .background(GeometryReader { inner in
                        Color.clear.preference(
                            key: DetailScrollKey.self,
                            value: ScrollMetric(
                                offset: -inner.frame(in: .named("detailScroll")).minY,
                                contentHeight: inner.size.height,
                                viewportHeight: outer.size.height
                            )
                        )
                    })
                }
                .coordinateSpace(name: "detailScroll")
                .refreshable { await load(force: true) }
                .onChange(of: showTOC) { _ in }
                .toolbar(.hidden, for: .tabBar)
                .toolbar { toolbar }
                .sheet(isPresented: $showTOC) { tocSheet(proxy: proxy) }
                .fullScreenCover(isPresented: Binding(
                    get: { !viewerURLs.isEmpty },
                    set: { if !$0 { viewerURLs = [] } }
                )) {
                    PhotoViewer(urls: viewerURLs, selectedIndex: $viewerIndex) { viewerURLs = [] }
                }
                .sheet(item: $safari) { wrapper in
                    SafariView(url: wrapper.url).ignoresSafeArea()
                }
                .overlay(alignment: .top) { progressBar }
                .task { await load(force: false) }
                .navigationDestination(for: Post.self) { DetailView(post: $0) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { Prefs.recordHistory(post.id) }
            }
        }
    }

    // MARK: 正文

    @ViewBuilder
    private var bodyContent: some View {
        if let cover = post.coverURL {
            CachedImage(url: cover, cornerRadius: 0)
                .frame(height: 210)
                .clipped()
                .onTapGesture { openViewer(url: cover.absoluteString) }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text(post.plainTitle)
                .font(.system(size: 24, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            metaRow

            Divider().padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)

        if isLoading && blocks.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在加载正文…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if let errorMessage, blocks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") { Task { await load(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .padding(.horizontal, 32)
        } else {
            ArticleView(
                blocks: blocks,
                fontSize: fontSize,
                onLinkTap: { handleLink($0) },
                onImageTap: { url, _ in openViewer(url: url) }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }

        if !post.tagNames.isEmpty {
            tagSection
        }

        if !related.isEmpty {
            relatedSection
        }

        neighborSection

        commentsSection

        Color.clear.frame(height: 40)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if !post.authorName.isEmpty {
                Label(post.authorName, systemImage: "person.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(post.displayDate, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(post.categoryNames, id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var tagSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(post.tagNames, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("相关阅读")
            ForEach(related) { item in
                NavigationLink(value: item) {
                    PostCardRow(post: item, showCategory: false)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var neighborSection: some View {
        VStack(spacing: 8) {
            neighborRow(title: "上一篇", post: previousPost, icon: "chevron.up")
            neighborRow(title: "下一篇", post: nextPost, icon: "chevron.down")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func neighborRow(title: String, post item: Post?, icon: String) -> some View {
        Group {
            if let item {
                NavigationLink(value: item) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(item.plainTitle)
                                .font(.footnote)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                EmptyView()
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !comments.isEmpty {
                sectionTitle("评论 \(comments.count)")
                ForEach(comments) { c in
                    commentRow(c)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let url = c.avatarURL {
                CachedImage(url: url, cornerRadius: 20)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(Text(String(c.authorName.prefix(1))).font(.caption))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.authorName)
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(String(c.date.prefix(10)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                RichText(
                    attributed: InlineRenderer.render(
                        [Inline.text(c.content.plainText)],
                        fontSize: max(fontSize - 3, 13),
                        color: UIColor.secondaryLabel
                    ),
                    lineSpacing: 4
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
    }

    // MARK: 目录

    private func tocSheet(proxy: ScrollViewProxy) -> some View {
        NavigationStack {
            List {
                ForEach(Array(headings.enumerated()), id: \.offset) { _, h in
                    Button {
                        showTOC = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation { proxy.scrollTo(h.anchor, anchor: .top) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(h.text)
                                .font(h.level == 2 ? .subheadline : .footnote)
                                .foregroundStyle(h.level == 2 ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.leading, CGFloat((h.level - 2) * 12))
                    }
                }
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showTOC = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: 工具栏

    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if !headings.isEmpty {
                Button {
                    showTOC = true
                } label: {
                    Image(systemName: "list.bullet")
                }
            }
            ShareLink(item: post.link) {
                Image(systemName: "square.and.arrow.up")
            }
            Menu {
                Button {
                    app.toggleFavorite(post)
                } label: {
                    Label(
                        app.isFavorite(post.id) ? "取消收藏" : "收藏",
                        systemImage: app.isFavorite(post.id) ? "star.fill" : "star"
                    )
                }
                Button {
                    if let url = URL(string: post.link) { safari = IdentifiableURL(url: url) }
                } label: {
                    Label("用 Safari 打开原文", systemImage: "safari")
                }
                Button {
                    UIPasteboard.general.string = post.link
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: 阅读进度

    @State private var progress: CGFloat = 0

    private var progressBar: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: geo.size.width, height: 2.5)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(progress, 1)) * geo.size.width, height: 2.5)
                }
                Spacer()
            }
        }
        .allowsHitTesting(false)
        .onPreferenceChange(DetailScrollKey.self) { metric in
            let scrollable = max(metric.contentHeight - metric.viewportHeight, 1)
            let value = metric.offset / scrollable
            progress = max(0, min(1, value))
        }
    }

    // MARK: 数据

    private func load(force: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let detail = try await WPClient.shared.post(id: post.id, refresh: force)
            Cache.save(post: detail)
            blocks = ArticleParser.parse(html: detail.content.rendered, baseURL: URL(string: detail.link))

            async let rel = WPClient.shared.related(
                category: detail.primaryCategoryID,
                exclude: detail.id
            )
            async let prev = WPClient.shared.neighbor(post: detail, direction: .previous)
            async let nxt = WPClient.shared.neighbor(post: detail, direction: .next)
            async let cms = WPClient.shared.comments(postID: detail.id)

            let (r, p, n, c) = await (
                (try? rel) ?? [],
                (try? prev) ?? nil,
                (try? nxt) ?? nil,
                (try? cms) ?? []
            )
            related = r
            previousPost = p
            nextPost = n
            comments = c
        } catch {
            if blocks.isEmpty {
                errorMessage = FeedModel.hint(for: error)
            }
        }
    }

    // MARK: 交互

    private func openViewer(url: String) {
        let all = imageURLs
        guard let idx = all.firstIndex(of: url) else {
            viewerURLs = [url]
            viewerIndex = 0
            return
        }
        viewerURLs = all
        viewerIndex = idx
    }

    private func handleLink(_ url: URL) {
        let absolute = url.absoluteString
        guard ArticleParser.isInternalArticle(absolute) else {
            safari = IdentifiableURL(url: url)
            return
        }
        if let id = ArticleParser.postID(from: url), id != post.id {
            Task {
                do {
                    let target = try await WPClient.shared.post(id: id)
                    navPath.wrappedValue.append(target)
                } catch {
                    safari = IdentifiableURL(url: url)
                }
            }
        } else {
            safari = IdentifiableURL(url: url)
        }
    }
}

// MARK: - 预览数据

#if DEBUG
extension DetailView {
    static func previewPost() -> Post {
        Post(
            id: 3149,
            date: "2026-10-09T10:00:00",
            link: "https://www.zhujitown.com/3149.html",
            title: "示例：金秋特惠活动",
            excerpt: "这是一段用于预览的摘要文本。"
        )
    }
}
#endif
