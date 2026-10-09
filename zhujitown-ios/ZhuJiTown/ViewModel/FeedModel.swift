import Foundation
import SwiftUI

/// 文章流：分页 / 下拉刷新 / 分类筛选 / 关键词搜索 / 草稿
@MainActor
final class FeedModel: ObservableObject {

    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var totalPosts = 0

    var categoryID: Int?
    var query: String = ""
    var includeDrafts: Bool = false

    private var page = 1
    private var totalPages = 1
    private let perPage = 20

    @Published private(set) var generation = UUID()

    var isEmpty: Bool { posts.isEmpty && !isLoading }

    /// 列表筛选条件变化时调用
    func reload(category: Int? = nil, query: String? = nil) async {
        if let category { categoryID = category }
        if let query { self.query = query }
        page = 1
        totalPages = 1
        generation = UUID()
        await load(reset: true)
    }

    /// 下拉刷新
    func refresh() async {
        page = 1
        await load(reset: true)
    }

    func load(reset: Bool) async {
        guard !isLoading else { return }
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let result = try await WPClient.shared.posts(
                page: page,
                perPage: perPage,
                category: categoryID,
                search: query.isEmpty ? nil : query,
                status: includeDrafts ? "draft" : nil
            )
            totalPages = result.totalPages
            totalPosts = result.total
            if page == 1 {
                posts = result.items
            } else {
                var seen = Set(posts.map(\.id))
                posts.append(contentsOf: result.items.filter { seen.insert($0.id).inserted })
            }
            page += 1
        } catch {
            if page == 1 && posts.isEmpty {
                errorMessage = Self.hint(for: error)
            } else {
                errorMessage = nil
            }
        }
    }

    /// 滚动到倒数第 N 条时加载下一页
    func loadMoreIfNeeded(current post: Post) async {
        guard let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }
        guard idx >= posts.count - 3 else { return }
        guard page <= totalPages else { return }
        guard !isLoadingMore, !isLoading else { return }
        await load(reset: false)
    }

    var hasMore: Bool { page <= totalPages }

    static func hint(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "没有网络，试试下拉刷新"
            case NSURLErrorTimedOut: return "站点响应超时，稍后再试"
            case NSURLErrorCannotFindHost: return "找不到站点，检查设置里的站点地址"
            default: return "加载失败：\(ns.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}
