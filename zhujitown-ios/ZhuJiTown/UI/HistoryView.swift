import SwiftUI

/// 个人中心 → 阅读历史（本地记录的已读文章）
struct HistoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var posts: [Post] = []
    @State private var loading = false

    var body: some View {
        Group {
            if posts.isEmpty {
                if loading {
                    ProgressView("加载中…")
                } else {
                    PlaceholderState(
                        systemImage: "clock",
                        title: "还没有阅读记录",
                        subtitle: "看过的文章会自动记录在这里"
                    )
                }
            } else {
                List {
                    ForEach(posts) { post in
                        NavigationLink(value: post) {
                            PostCardRow(post: post)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("阅读历史")
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let ids = Prefs.history
        guard !ids.isEmpty else { return }
        do {
            posts = try await WPClient.shared.posts(ids: Array(ids.prefix(100)))
        } catch {
            app.notice = "读取历史失败：\(error.localizedDescription)"
        }
    }
}
