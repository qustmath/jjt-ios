import AVFoundation
import SwiftUI

/// 扫一扫（对齐安卓 ScanScreen：相机扫码 → QR 协议解析 → 统一深链路由）
/// 支持：friend 用户主页 / post 帖子 / group 群聊 / pageant 选美 / activity 活动 / url 外部浏览器；
/// task/topic 与安卓一致暂未实现（提示）
struct ScanView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var cameraDenied = false
    @State private var lastResult: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraDenied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Noir.gold)
                    Text("需要相机权限才能扫码")
                        .font(.system(size: 14))
                        .foregroundStyle(Noir.ivory)
                    Button("去设置开启") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(LinearGradient(colors: [Noir.crimson, Noir.crimsonHot], startPoint: .leading, endPoint: .trailing)))
                }
            } else {
                CameraPreview(onDetect: handleScan)
                    .ignoresSafeArea()

                // 鎏金取景框
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Noir.gold.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 240, height: 240)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text(lastResult ?? "对准二维码，自动识别")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .padding(.bottom, 120)
                }
            }

            // 顶栏
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    Spacer()
                    Text("扫一扫")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .tracking(3)
                        .foregroundStyle(Noir.goldText)
                    Spacer()
                    Spacer().frame(width: 50)
                }
                .padding(.top, 16)
                Spacer()
            }
        }
        .task {
            // 相机权限：首次弹授权，拒绝进引导态
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: break
            case .notDetermined:
                cameraDenied = await AVCaptureDevice.requestAccess(for: .video) == false
            default:
                cameraDenied = true
            }
        }
        .jjtPageGestures()
    }

    /// 识别结果 → QR 协议（对齐安卓 QrCodeData t=friend/group/post/task/url/topic/activity + pageant）→ 深链
    private func handleScan(_ raw: String) {
        guard lastResult == nil else { return } // 只处理首个结果
        // 非 JSON 内容：按文本提示（对齐安卓 toast 未识别）
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["t"] as? String else {
            lastResult = "无法识别的二维码"
            return
        }
        switch t {
        case "friend", "post", "group", "activity":
            dismiss()
            NotificationCenter.default.post(name: .jjtDeepLink, object: obj)
        case "pageant":
            dismiss()
            NotificationCenter.default.post(name: .jjtDeepLink, object: ["t": "pageant"])
        case "url":
            if let link = obj["url"] as? String, let url = URL(string: link),
               url.scheme == "http" || url.scheme == "https" {
                dismiss()
                UIApplication.shared.open(url)
            } else {
                lastResult = "链接无效"
            }
        default:
            // task/topic 等与安卓一致暂未实现
            lastResult = "该类型暂未支持"
        }
    }
}

// MARK: - 相机预览（AVCaptureMetadataOutput 原生 QR 识别）

private struct CameraPreview: UIViewControllerRepresentable {

    let onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> CameraVC {
        CameraVC(onDetect: onDetect)
    }

    func updateUIViewController(_ uiViewController: CameraVC, context: Context) {}
}

private final class CameraVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    let onDetect: (String) -> Void
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    init(onDetect: @escaping (String) -> Void) {
        self.onDetect = onDetect
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        onDetect(value)
    }
}
