import SwiftUI
import SceneKit
import GLTFSceneKit
import CryptoKit

/// 3D 礼物渲染（对齐安卓 Gift3DRender：glb + 自转 0.7rad/s + 上下浮动 + heart3d 心跳）
/// source：内置资产名（diamond/crown3d/heart3d/chalice/serpent）或后台上传的 glb URL
struct Gift3DView: UIViewRepresentable {
    let source: String
    var interactive: Bool = false

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.allowsCameraControl = interactive
        view.autoenablesDefaultLighting = false

        let scene = SCNScene()
        view.scene = scene

        // 相机
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.position = SCNVector3(0, 0.4, 4.4)
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam

        // 暗夜三灯（对齐安卓：红主光 + 金辅光 + 环境托底）
        func pointLight(_ color: UIColor, _ intensity: CGFloat, _ pos: SCNVector3) {
            let node = SCNNode()
            let light = SCNLight()
            light.type = .omni
            light.color = color
            light.intensity = intensity
            node.light = light
            node.position = pos
            scene.rootNode.addChildNode(node)
        }
        pointLight(UIColor(red: 1.0, green: 0.10, blue: 0.16, alpha: 1), 700, SCNVector3(3, 2.5, 3))
        pointLight(UIColor(red: 0.95, green: 0.62, blue: 0.15, alpha: 1), 350, SCNVector3(-3, 1.5, 2))
        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.35, alpha: 1)
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // 异步加载模型
        Task { [weak view] in
            guard let modelScene = await Self.loadScene(source) else { return }
            await MainActor.run {
                guard let view, let root = view.scene?.rootNode else { return }
                let holder = SCNNode()
                let model = modelScene.rootNode
                // 归一化：最大边缩到 ~1.6，居中到原点
                let (bmin, bmax) = model.boundingBox
                let dim = max(bmax.x - bmin.x, max(bmax.y - bmin.y, bmax.z - bmin.z))
                let s: Float = dim > 0 ? 1.6 / dim : 1
                model.scale = SCNVector3(s, s, s)
                let center = SCNVector3((bmin.x + bmax.x) / 2 * s, (bmin.y + bmax.y) / 2 * s, (bmin.z + bmax.z) / 2 * s)
                model.position = SCNVector3(-center.x, -center.y, -center.z)
                holder.addChildNode(model)
                root.addChildNode(holder)

                // 自转 0.7rad/s（一周 ≈ 9s）
                holder.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 9)))
                // 上下浮动 sin(t*1.6)*0.08（周期 ≈ 3.93s）
                holder.runAction(.repeatForever(.sequence([
                    .moveBy(x: 0, y: 0.08, z: 0, duration: 1.965),
                    .moveBy(x: 0, y: -0.08, z: 0, duration: 1.965),
                ])))
                // heart3d 心跳缩放 1±0.06（sin 3.2rad/s ≈ 周期 1.96s）
                if source == "heart3d" {
                    holder.runAction(.repeatForever(.sequence([
                        .scale(to: 1.06, duration: 0.49),
                        .scale(to: 1.0, duration: 0.49),
                        .scale(to: 0.97, duration: 0.49),
                        .scale(to: 1.0, duration: 0.49),
                    ])))
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - 模型加载

    /// GLTFSceneKit 是 2018 年的老库，解析放在主线程 + 全局串行（并发解析疑似崩溃源）
    private static func loadScene(_ source: String) async -> SCNScene? {
        await GLBLoadQueue.shared.enqueue {
            let url: URL?
            if source.hasPrefix("http") {
                url = await GiftAssetCache.download(source, ext: "glb")
            } else {
                // 内置资产（JJT/Resources/gifts/*.glb）
                url = Bundle.main.url(forResource: source, withExtension: "glb", subdirectory: "gifts")
                    ?? Bundle.main.url(forResource: source, withExtension: "glb")
            }
            guard let url else { return nil }
            // 必须绕开 GLTFSceneSource：其 init(url:) 走 self.init() 空构造（URL 不进基类），
            // 且只覆写 scene(options:)；无参 .scene() 落到基类 -[SCNSceneSource scene]
            // → C3DSceneSourceGetURL 读空指针 → SIGSEGV。直接用 GLTFUnarchiver 解析。
            return try? GLTFUnarchiver(url: url).loadScene()
        }
    }
}

/// GLB 解析全局串行队列（主线程执行）
@MainActor
final class GLBLoadQueue {
    static let shared = GLBLoadQueue()
    private var running = false
    private var waiters: [() -> Void] = []

    func enqueue<T>(_ work: @escaping () async -> T?) async -> T? {
        if running {
            await withCheckedContinuation { cont in
                waiters.append { cont.resume() }
            }
        }
        running = true
        let result = await work()
        running = false
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next()
        }
        return result
    }
}

/// glb 素材下载缓存（对齐安卓 GiftAssetCache：md5 命名，已存在直接用）
enum GiftAssetCache {

    static func download(_ urlString: String, ext: String) async -> URL? {
        guard let url = URL(string: urlString) else { return nil }
        let fm = FileManager.default
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gift_assets", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let digest = Insecure.SHA1.hash(data: Data(urlString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let file = dir.appendingPathComponent("\(digest).\(ext)")
        if fm.fileExists(atPath: file.path) { return file }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            try? fm.removeItem(at: file)
            try fm.moveItem(at: tmp, to: file)
            return file
        } catch {
            return nil
        }
    }
}
