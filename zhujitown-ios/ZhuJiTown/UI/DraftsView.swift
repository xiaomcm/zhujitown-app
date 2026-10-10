import SwiftUI

/// 个人中心 → 草稿箱（仅管理员 / canManage 可见）
struct DraftsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.draftPosts.isEmpty {
                if app.draftLoading {
                    ProgressView("加载中…")
                } else {
                    PlaceholderState(
                        systemImage: "pencil.line",
                        title: "没有草稿",
                        subtitle: "具备管理权限时，这里会显示站点上的草稿"
                    )
                }
            } else {
                List {
                    ForEach(app.draftPosts) { post in
                        NavigationLink(value: post) {
                            PostCardRow(post: post)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("草稿箱")
        .task { await app.loadDrafts() }
    }
}
