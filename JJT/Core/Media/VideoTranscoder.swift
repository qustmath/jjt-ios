import AVFoundation
import CoreTransferable
import UIKit

/// 发帖视频处理（对齐安卓 VideoTranscoder，ADR-0010：统一转 720p/H.264 + 抽封面帧）
enum VideoTranscoder {

    /// 视频时长（秒）
    static func durationSeconds(_ url: URL) async -> Int {
        let asset = AVURLAsset(url: url)
        let d = try? await asset.load(.duration)
        let sec = d.map { CMTimeGetSeconds($0) } ?? 0
        return Int(sec.rounded())
    }

    /// 抽首帧封面（jpeg data）
    static func captureCover(_ url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1080, height: 1080)
        guard let shot = try? await gen.image(at: .zero) else { return nil }
        return UIImage(cgImage: shot.image).jpegData(compressionQuality: 0.85)
    }

    /// 转码为 720p H.264 mp4，输出到临时目录，返回文件 URL（失败返回 nil）
    static func transcode720p(_ url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("postvideo_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else { return nil }
        return out
    }
}

/// PhotosPicker 视频 Transferable：把相册视频复制到临时目录拿到文件 URL
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedVideo(url: dst)
        }
    }
}
