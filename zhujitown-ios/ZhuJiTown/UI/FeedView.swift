import SwiftUI
import SafariServices

struct FeedView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var feed = FeedModel()

    @State private var selectedCategory: Int? = nil
    @State private var searchText = ""
    @State private var showDrafts = false
    @State private var safariURL: IdentifiableURL?
    @State private var searchTask: Task<Void, Never>?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("主机镇")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarItems }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .autocorrectionDisabled()
                .refreshable { await feed.refresh() }
                .navigationDestination(for: Post.self) { post in
                    DetailView(post: post)
                }
                .environment(\.navPath, $path)
                .sheet(item: $safariURL) { wrapper in
                    SafariView(url: wrapper.url).ignoresSafeArea()
                }
                .task { await initialLoad() }
                .onChange(of: selectedCategory) { _ in Task { await feed.reload(category: selectedCategory) } }
                .onChange(of: searchText) { value in scheduleSearch(value) }
                .onChange(of: showDrafts) { value in
                    feed.includeDrafts = value
                    Task { await feed.reload(query: searchText) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .siteChanged)) { _ in
                    Task { await feed.reload() }
                }
        }
    }

    // MARK: 主体

    @ViewBuilder
    private var content: some View {
        List {
            if !app.categories.isEmpty {
                Section {
                    CategoryChips(categories: app.categories, selected: $selectedCategory)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(feed.posts) { post in
                    NavigationLink(value: post) {
                        if feed.posts.first?.id == post.id {
                            HeadlineCard(post: post)
                        } else {
                            PostCardRow(post: post)
                        }
                    }
                    .listRowSeparator(.visible, edges: .bottom)
                    .task { await feed.loadMoreIfNeeded(current: post) }
                }

                if feed.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if feed.isLoading && feed.posts.isEmpty { LoadingOverlay() }
        }
        .overlay {
            if let message = feed.errorMessage, feed.posts.isEmpty {
                PlaceholderState(
                    systemImage: "wifi.exclamationmark",
                    title: "加载失败",
                    subtitle: message,
                    actionTitle: "重试"
                ) {
                    Task { await feed.reload(query: searchText) }
                }
            } else if feed.isEmpty && !feed.isLoading {
                PlaceholderState(
                    systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass",
                    title: searchText.isEmpty ? "还没有内容" : "没有匹配的文章",
                    subtitle: searchText.isEmpty ? nil : "换个关键词试试",
                    actionTitle: searchText.isEmpty ? "刷新" : "清空搜索"
                ) {
                    if searchText.isEmpty {
                        Task { await feed.reload() }
                    } else {
                        searchText = ""
                    }
                }
            }
        }
    }

    // MARK: 工具栏

    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if app.canManage {
                Menu {
                    Toggle("草稿箱", isOn: $showDrafts)
                    Divider()
                    Button {
                        if let url = URL(string: Prefs.siteURL) { safariURL = IdentifiableURL(url: url) }
                    } label: {
                        Label("打开站点", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            } else {
                Button {
                    if let url = URL(string: Prefs.siteURL) { safariURL = IdentifiableURL(url: url) }
                } label: {
                    Image(systemName: "safari")
                }
            }
        }
    }

    // MARK: 逻辑

    private func initialLoad() async {
        await app.bootstrap()
        await feed.reload()
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await feed.reload(query: value)
        }
    }
}

// MARK: - 通用组件

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).opacity(0.4).ignoresSafeArea()
            ProgressView("加载中…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// 站外链接用 SFSafariViewController 打开：保 Cookie、有阅读器、能返回 App
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredControlTintColor = .tintColor
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
