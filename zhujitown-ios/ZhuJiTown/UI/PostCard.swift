import SwiftUI

// MARK: - 紧凑卡片

struct PostCardRow: View {
    let post: Post
    var showCategory = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(post.plainTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(post.plainExcerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                metaLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            thumbnail
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = post.coverURL {
            CachedImage(url: url, cornerRadius: 6)
                .frame(width: 112, height: 78)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            if showCategory, let first = post.categoryNames.first {
                Text(first)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            if post.status != "publish" {
                Text(post.status == "draft" ? "草稿" : post.status)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Text(post.displayDate)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }
}

// MARK: - 头条大图卡

struct HeadlineCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = post.coverURL {
                CachedImage(url: url, cornerRadius: 10)
                    .frame(height: 190)
            }
            Text(post.plainTitle)
                .font(.system(size: 21, weight: .bold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(post.plainExcerpt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let c = post.categoryNames.first {
                    Text(c)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                Text(post.displayDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - 分类筛选条

struct CategoryChips: View {
    let categories: [Category]
    @Binding var selected: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", count: nil, isOn: selected == nil) { selected = nil }
                ForEach(categories) { c in
                    chip(title: c.name, count: c.count, isOn: selected == c.id) {
                        selected = (selected == c.id) ? nil : c.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(
        title: String,
        count: Int?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline)
                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(isOn ? Color.accentColor.opacity(0.85) : .tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay {
                if isOn {
                    Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - 空 / 错误占位

struct PlaceholderState: View {
    var systemImage: String
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .listRowBackground(Color.clear)
    }
}
