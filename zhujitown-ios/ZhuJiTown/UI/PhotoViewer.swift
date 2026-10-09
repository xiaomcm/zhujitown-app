import SwiftUI

/// 全屏图片查看器：双击放大、双指缩放、拖拽下滑关闭
struct PhotoViewer: View {

    let urls: [String]
    @Binding var selectedIndex: Int
    let onClose: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var uiImages: [String: UIImage] = [:]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    ZoomableImage(image: uiImages[url]) {
                        await loadIfNeeded(url)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            closeButton
        }
        .offset(y: dragOffset.height)
        .opacity(opacity(for: dragOffset))
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation }
                .onEnded { value in
                    if abs(value.translation.height) > 140 {
                        onClose()
                    } else {
                        withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
                    }
                }
        )
        .statusBar(hidden: true)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(11)
                .background(.black.opacity(0.35), in: Circle())
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
    }

    private func opacity(for offset: CGSize) -> Double {
        let progress = abs(offset.height) / 400
        return max(0.35, 1 - progress)
    }

    @MainActor
    private func loadIfNeeded(_ urlString: String) async {
        guard uiImages[urlString] == nil, let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let img = UIImage(data: data) { uiImages[urlString] = img }
        } catch { }
    }
}

// MARK: - 可缩放图片（UIScrollView）

struct ZoomableImage: UIViewRepresentable {
    let image: UIImage?
    let load: () async -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.tag = 101
        scroll.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        guard let imageView = uiView.viewWithTag(101) as? UIImageView else { return }
        if imageView.image == nil, let image {
            imageView.image = image
            imageView.sizeToFit()
            let w = uiView.bounds.width == 0 ? UIScreen.main.bounds.width : uiView.bounds.width
            let h = uiView.bounds.height == 0 ? UIScreen.main.bounds.height : uiView.bounds.height
            let scale = min(w / image.size.width, h / image.size.height, 1)
            imageView.frame = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
            uiView.contentSize = imageView.frame.size
            centerContent(scroll: uiView)
        } else if imageView.image == nil {
            Task { await load() }
        }
        if uiView.bounds != context.coordinator.lastBounds {
            context.coordinator.lastBounds = uiView.bounds
            DispatchQueue.main.async { centerContent(scroll: uiView) }
        }
    }

    private func centerContent(scroll: UIScrollView) {
        guard let imageView = scroll.viewWithTag(101) as? UIImageView else { return }
        let offsetX = max((scroll.bounds.width - scroll.contentSize.width) * 0.5, 0)
        let offsetY = max((scroll.bounds.height - scroll.contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(
            x: scroll.contentSize.width * 0.5 + offsetX,
            y: scroll.contentSize.height * 0.5 + offsetY
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var lastBounds: CGRect = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.viewWithTag(101)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            UIView.animate(withDuration: 0.25) {
                scroll.zoomScale = scroll.zoomScale > 1.01 ? 1 : 2.4
            }
        }
    }
}

// MARK: - 图片查看器容器

struct ImageViewerSheet: ViewModifier {
    @Binding var urls: [String]
    @Binding var index: Int
    var isPresented: Bool

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(
            get: { isPresented && !urls.isEmpty },
            set: { _ in }
        )) {
            PhotoViewer(urls: urls, selectedIndex: $index) {
                urls = []
            }
        }
    }
}
