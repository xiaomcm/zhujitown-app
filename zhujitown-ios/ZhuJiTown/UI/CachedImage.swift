import SwiftUI
import Network

// MARK: - 网络状态（图片按需加载用）

final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()

    /// true 表示当前是非 Wi-Fi 网络（蜂窝 / 受限）
    @Published var isExpensive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.isExpensive = path.isExpensive }
        }
        monitor.start(queue: DispatchQueue(label: "com.zhujitown.netmonitor"))
    }
}

// MARK: - 图片加载

@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false
    @Published var isLoading = true

    private static let memCache = NSCache<NSURL, UIImage>()
    private var task: URLSessionDataTask?

    func load(_ url: URL) {
        isLoading = true
        if let hit = Self.memCache.object(forKey: url as NSURL) {
            image = hit
            isLoading = false
            return
        }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil, let img = UIImage(data: data) else {
                DispatchQueue.main.async { self?.isLoading = false; self?.failed = true }
                return
            }
            Self.memCache.setObject(img, forKey: url as NSURL)
            DispatchQueue.main.async {
                self?.image = img
                self?.isLoading = false
            }
        }
        task?.resume()
    }

    func cancel() { task?.cancel() }
}

// MARK: - 图片视图

/// 带内存缓存 + 磁盘缓存（URLCache）的图片视图，遵循「图片加载策略」设置
struct CachedImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 8

    @StateObject private var loader = ImageLoader()
    @State private var forceLoad = false

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch policy {
        case .loadNow:
            realImage
        case .tapToLoad:
            Button {
                forceLoad = true
            } label: {
                placeholder(text: "点击查看图片", systemImage: "photo")
            }
            .buttonStyle(.plain)
        case .blocked:
            placeholder(text: "无图模式", systemImage: "photo.slash")
        }
    }

    private enum Decision { case loadNow, tapToLoad, blocked }

    private var policy: Decision {
        guard !forceLoad else { return .loadNow }
        switch Prefs.imageQuality {
        case .always: return .loadNow
        case .never: return .blocked
        case .wifi: return NetworkMonitor.shared.isExpensive ? .tapToLoad : .loadNow
        }
    }

    @ViewBuilder
    private var realImage: some View {
        if let ui = loader.image {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .allowsHitTesting(false)
        } else if loader.failed {
            placeholder(text: "图片加载失败", systemImage: "exclamationmark.triangle")
        } else {
            ZStack {
                Rectangle().fill(Color.secondary.opacity(0.08))
                ProgressView()
                    .controlSize(.small)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .task(id: url?.absoluteString ?? "") {
                loader.cancel()
                if let url { loader.load(url) }
            }
        }
    }

    private func placeholder(text: String, systemImage: String) -> some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.08))
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(text)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
