import SwiftUI

/// 个人中心 → 我的评论
struct MyCommentsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.myComments.isEmpty {
                if app.myLoading {
                    ProgressView("加载中…")
                } else {
                    PlaceholderState(
                        systemImage: "bubble.left.and.text",
                        title: "还没有评论",
                        subtitle: "你发表的评论会出现在这里"
                    )
                }
            } else {
                List {
                    ForEach(app.myComments) { c in
                        NavigationLink {
                            PostDetailLoader(postID: c.post)
                        } label: {
                            CommentRow(comment: c)
                        }
                    }
                    if app.myComments.count < app.myCommentsTotal {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .onAppear { Task { await app.loadMoreMyComments() } }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("我的评论")
        .task {
            if app.myComments.isEmpty { await app.loadMyComments() }
        }
        .refreshable { await app.loadMyComments() }
    }
}

private struct CommentRow: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(comment.authorName.isEmpty ? "匿名" : comment.authorName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(Post.formatDate(comment.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(comment.content.plainText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.vertical, 6)
    }
}
