import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QR 生成与装饰（对齐安卓 generateQrCode + cornerFrame）

/// 生成二维码 UIImage（对齐安卓 ZXing：EC Level M，UTF-8）
func qrCodeImage(_ content: String, side: CGFloat = 512) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(content.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scale = side / output.extent.width
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}

/// 鎏金取景框：卡片四角 L 形金臂（对齐安卓 cornerFrame）
struct CornerFrame: View {
    var color: Color = Noir.goldLight.opacity(0.8)
    var margin: CGFloat = 14
    var arm: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // 左上
                p.move(to: CGPoint(x: margin, y: margin + arm)); p.addLine(to: CGPoint(x: margin, y: margin)); p.addLine(to: CGPoint(x: margin + arm, y: margin))
                // 右上
                p.move(to: CGPoint(x: w - margin - arm, y: margin)); p.addLine(to: CGPoint(x: w - margin, y: margin)); p.addLine(to: CGPoint(x: w - margin, y: margin + arm))
                // 左下
                p.move(to: CGPoint(x: margin, y: h - margin - arm)); p.addLine(to: CGPoint(x: margin, y: h - margin)); p.addLine(to: CGPoint(x: margin + arm, y: h - margin))
                // 右下
                p.move(to: CGPoint(x: w - margin - arm, y: h - margin)); p.addLine(to: CGPoint(x: w - margin, y: h - margin)); p.addLine(to: CGPoint(x: w - margin, y: h - margin - arm))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}

/// 鎏金 QR 卡片（我的二维码 / 邀请页共用）
struct GoldQrCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(28)
            .background(LinearGradient(colors: [Color.white.opacity(0.045), Color.white.opacity(0.02)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Noir.gold.opacity(0.35), lineWidth: 1))
            .overlay(CornerFrame())
    }
}

// MARK: - 我的二维码（对齐安卓 MyQrCodeScreen）

struct MyQrCodeView: View {

    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var qr: UIImage?

    var body: some View {
        ZStack {
            Noir.noir.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                GoldQrCard {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                        if let qr {
                            Image(uiImage: qr)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 220, height: 220)
                                .padding(14)
                        } else {
                            ProgressView().tint(Noir.gold)
                                .frame(width: 220, height: 220)
                        }
                    }
                    .frame(width: 248, height: 248)
                }
                Text("扫一扫加好友")
                    .font(.system(size: 12))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 24)
                Text("SCAN TO CONNECT")
                    .font(.system(size: 9, design: .serif))
                    .italic()
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear { makeQr() }
    }

    private var topBar: some View {
        HStack {
            Button {
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Noir.goldLight)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Noir.hairlineGold, lineWidth: 1))
            }
            Spacer()
            Text("我的二维码")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .tracking(4)
                .foregroundStyle(Noir.goldText)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func makeQr() {
        // 对齐安卓：{"t":"friend","uid":<id>}
        Task {
            guard let user = try? await UserAPI.getUserInfo() else { return }
            qr = qrCodeImage("{\"t\":\"friend\",\"uid\":\(user.id)}")
        }
    }
}
