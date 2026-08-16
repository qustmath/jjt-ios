import SwiftUI

/// 图片全屏预览（对齐安卓 ImagePreviewDialog）：
/// 左右滑动切换、双指缩放/拖动、双击放大还原、单击关闭。
struct ImagePreviewViewer: View {
    let images: [String]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    /// 任一页处于放大态（拖动图片时屏蔽翻页手势干扰由系统协调，此处仅上报）
    @State private var zoomed = false

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
                        onZoomChange: { zoomed = $0 },
                        onTap: { dismiss() }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onChange(of: index) { _, _ in zoomed = false }

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

/// 可缩放图片：双指缩放、放大后拖动、双击放大/还原、单击关闭
private struct ZoomableImage: View {
    let urlString: String
    var onZoomChange: (Bool) -> Void
    var onTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        AsyncImage(url: webImageURL(urlString)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Color.clear.overlay(ProgressView().tint(.white.opacity(0.5)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .offset(offset)
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if scale > 1.05 { reset() } else {
                        scale = 2.5
                        lastScale = 2.5
                        onZoomChange(true)
                    }
                }
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded { if scale <= 1.05 { onTap() } }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { v in
                    scale = max(1, lastScale * v)
                    onZoomChange(scale > 1.05)
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale <= 1.05 { withAnimation { reset() } }
                }
        )
        // 拖动手势仅在放大态挂载——否则会把未放大时的左右翻页滑动吃掉
        .gesture(
            DragGesture()
                .onChanged { v in
                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                    height: lastOffset.height + v.translation.height)
                }
                .onEnded { _ in lastOffset = offset },
            including: scale > 1.05 ? .all : .none
        )
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        onZoomChange(false)
    }
}
