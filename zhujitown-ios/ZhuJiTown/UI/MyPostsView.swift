import SwiftUI

/// 个人中心 → 我的文章
struct MyPostsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.myPosts.isEmpty {
                if app.myLoading {
                    ProgressView("加载中…")
                } else {
                    PlaceholderState(
                        systemImage: "doc.text",
                        title: "还没有文章",
                        subtitle: "登录后在这里查看自己发表的内容"
                    )
                }
            } else {
                List {
                    ForEach(app.myPosts) { post in
                        NavigationLink(value: post) {
                            PostCardRow(post: post)
                        }
                    }
                    if app.myPosts.count < app.myPostsTotal {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .onAppear { Task { await app.loadMoreMyPosts() } }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("我的文章")
        .task {
            if app.myPosts.isEmpty { await app.loadMyPosts() }
        }
        .refreshable { await app.loadMyPosts() }
    }
}
