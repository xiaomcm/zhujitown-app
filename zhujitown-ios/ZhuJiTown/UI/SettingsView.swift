import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    @AppStorage(PrefKey.siteURL.rawValue) private var siteURL: String = AppConfig.siteURL
    @AppStorage(PrefKey.fontSize.rawValue) private var fontSize: Double = 17
    @AppStorage(PrefKey.imageQuality.rawValue) private var imageQualityRaw: String = "always"
    @AppStorage(PrefKey.appearance.rawValue) private var appearanceRaw: String = "auto"

    @State private var cacheSize = Cache.sizeDescription
    @State private var showClearConfirm = false

    private var imageQuality: Prefs.ImageQuality {
        get { Prefs.ImageQuality(rawValue: imageQualityRaw) ?? .always }
        set { imageQualityRaw = newValue.rawValue }
    }

    private var appearance: Prefs.Appearance {
        get { Prefs.Appearance(rawValue: appearanceRaw) ?? .auto }
        set { appearanceRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                siteSection
                readingSection
                cacheSection
                aboutSection
            }
            .navigationTitle("设置")
            .onAppear {
                cacheSize = Cache.sizeDescription
            }
        }
    }

    // MARK: 站点

    private var siteSection: some View {
        Section("站点") {
            TextField("https://www.zhujitown.com", text: $siteURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            Button("保存并重载") {
                let v = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty else { return }
                Prefs.siteURL = v.hasPrefix("http") ? v : "https://" + v
                siteURL = Prefs.siteURL
                NotificationCenter.default.post(name: .siteChanged, object: nil)
                Task { await app.loadCategories(force: true) }
            }
            Text("接口路径：\(Prefs.siteURL)/wp-json/wp/v2/")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 账号

    private var accountSection: some View {
        Section {
            if let s = app.session {
                HStack(spacing: 12) {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(s.name.prefix(1)).uppercased())
                                .font(.headline)
                                .foregroundStyle(AppTheme.accent)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.subheadline).fontWeight(.medium)
                        Text("已登录 · \(s.backend.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                NavigationLink("账号管理") { AccountView() }
                Button(role: .destructive) {
                    Task { await app.logout() }
                } label: { Text("退出登录") }
            } else {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack {
                        Text("登录 / 注册")
                        Spacer()
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                Text("登录用的是你网站的账号；若站点开放了注册，也可在 App 内直接注册。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("账号")
        }
    }

    // MARK: 阅读

    private var readingSection: some View {
        Section("阅读") {
            HStack {
                Text("正文字号")
                Spacer()
                Text("\(Int(fontSize)) pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $fontSize, in: 14...24, step: 1)
            previewText

            Picker("图片加载", selection: Binding(
                get: { imageQuality },
                set: { imageQuality = $0 }
            )) {
                ForEach(Prefs.ImageQuality.allCases) { q in
                    Text(q.label).tag(q)
                }
            }

            Picker("主题", selection: Binding(
                get: { appearance },
                set: { appearance = $0 }
            )) {
                ForEach(Prefs.Appearance.allCases) { a in
                    Text(a.label).tag(a)
                }
            }
        }
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("这是正文效果预览，可直接拖动滑块调整。")
                .font(.system(size: CGFloat(fontSize)))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 缓存

    private var cacheSection: some View {
        Section("离线缓存") {
            HStack {
                Text("占用空间")
                Spacer()
                Text(cacheSize).foregroundStyle(.secondary)
            }
            Button("刷新统计") {
                cacheSize = Cache.sizeDescription
                Task { await app.refreshFavorites() }
            }
            Button(role: .destructive) { showClearConfirm = true } label: {
                Text("清除全部缓存")
            }
            .alert("确认清除？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) { }
                Button("清除", role: .destructive) {
                    app.clearCache()
                    cacheSize = Cache.sizeDescription
                }
            } message: {
                Text("""
                会删除已缓存的正文。

                收藏列表本身会保留，但收藏文章的离线正文需要重新联网拉取。
                """)
            }
            Text("收藏成功后会自动缓存正文，断网也能继续阅读。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("v\(AppConfig.appVersion)").foregroundStyle(.secondary)
            }
            Link(destination: URL(string: Prefs.siteURL)!) {
                HStack {
                    Text("访问网站")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
            }
            Text("在 Safari 输入 \(AppConfig.urlScheme)://post/文章ID 可直接唤起 App 打开对应文章。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
