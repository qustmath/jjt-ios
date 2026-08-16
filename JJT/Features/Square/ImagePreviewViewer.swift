import SwiftUI

/// 图片全屏预览（对齐安卓 ImagePreviewDialog）：
/// 左右滑动切换、双指缩放/拖动、双击放大还原、单击关闭。
struct ImagePreviewViewer: View {
    let images: [String]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(images: [String], initialIndex: Int) {
        self.images = images
        self.initialIndex = initialIndex
        _index = State(initialValue: max(0, min(initialIndex, images.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    ZoomableImage(
                        urlString: images[i],
                        onTap: { dismiss() }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // 页码胶囊
            if images.count > 1 {
                VStack {
                    Spacer()
                    Text("\(index + 1)/\(images.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.bottom, 36)
                }
            }

            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.12))
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
    }
}

/// 可缩放图片：改用 UIScrollView 原生缩放手势（双指/拖动手感与系统照片一致，
/// 自绘手势有"不跟手"问题）
private struct ZoomableImage: UIViewRepresentable {
    let urlString: String
    var onTap: () -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 4
        sv.delegate = context.coordinator
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never

        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        sv.addSubview(iv)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        sv.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        sv.addGestureRecognizer(singleTap)

        context.coordinator.scrollView = sv
        context.coordinator.imageView = iv
        return sv
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.load(urlString)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var onTap: () -> Void = {}
        private var currentURL: String?
        private var task: URLSessionDataTask?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func load(_ urlString: String) {
            guard urlString != currentURL else { return }
            currentURL = urlString
            task?.cancel()
            imageView?.image = nil
            guard let url = webImageURL(urlString) else { return }
            task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.imageView?.image = img
                    self?.resetLayout()
                }
            }
            task?.resume()
        }

        private func resetLayout() {
            guard let sv = scrollView, let iv = imageView else { return }
            sv.zoomScale = 1
            iv.frame = CGRect(origin: .zero, size: sv.bounds.size)
            sv.contentSize = sv.bounds.size
            centerImage()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

        private func centerImage() {
            guard let sv = scrollView, let iv = imageView else { return }
            var frame = iv.frame
            frame.origin.x = frame.width < sv.bounds.width ? (sv.bounds.width - frame.width) / 2 : 0
            frame.origin.y = frame.height < sv.bounds.height ? (sv.bounds.height - frame.height) / 2 : 0
            iv.frame = frame
        }

        @objc func onDoubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = scrollView, let iv = imageView else { return }
            if sv.zoomScale > 1.05 {
                sv.setZoomScale(1, animated: true)
            } else {
                let p = g.location(in: iv)
                sv.zoom(to: CGRect(x: p.x - 50, y: p.y - 50, width: 100, height: 100), animated: true)
            }
        }

        @objc func onSingleTap(_ g: UITapGestureRecognizer) { onTap() }
    }
}
