import SwiftUI

/// 按文章 ID 拉取正文并展示详情（用于从「我的评论」跳转到原文）
struct PostDetailLoader: View {
    let postID: Int

    @EnvironmentObject private var app: AppModel
    @State private var post: Post?
    @State private var error: String?

    var body: some View {
        Group {
            if let p = post {
                DetailView(post: p)
            } else if let e = error {
                PlaceholderState(
                    systemImage: "exclamationmark.triangle",
                    title: "加载失败",
                    subtitle: e
                )
            } else {
                ProgressView("加载中…")
            }
        }
        .navigationTitle("文章")
        .task { await load() }
    }

    private func load() async {
        if let cached = Cache.loadPost(id: postID) {
            post = cached
            return
        }
        do {
            post = try await WPClient.shared.post(id: postID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
