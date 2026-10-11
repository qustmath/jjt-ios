import AVFoundation
import Foundation

/// 大厅语音消息录制（对齐安卓 LobbyVoiceRecorder：上限 60s、下限 1s 误触丢弃）。
/// iOS 用 AAC/m4a（腾讯 IM 语音消息支持），安卓端是 AMR——跨端互听由 IM 服务端转码兜底。
@MainActor
final class LobbyVoiceRecorder {

    struct Result {
        let path: String?
        let seconds: Int
        let error: String?
    }

    /// 录音上限（秒）：超时的收口由调用方（按住说话手势）触发 stop
    static let maxSeconds: Int = 60
    /// 低于 1 秒视为误触，丢弃
    static let minSeconds: Int = 1

    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    /// 麦克风权限（首次弹授权）
    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    /// 开始录音。返回 nil=已开始；返回文案=失败提示。
    func start() async -> String? {
        guard await requestPermission() else {
            return "需要麦克风权限才能发语音：请在设置里允许「荆棘兔」使用麦克风"
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("lobby_voice_\(Int64(Date().timeIntervalSince1970 * 1000))).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            guard rec.record() else {
                return "录音启动失败，请重试"
            }
            recorder = rec
            startedAt = Date()
            return nil
        } catch {
            return "录音启动失败：\(error.localizedDescription)"
        }
    }

    /// 停止录音（松手发送）。低于 1s 视为误触：丢弃文件，返回「说话时间太短」提示（对齐安卓）。
    func stop() -> Result {
        guard let rec = recorder, let startedAt else {
            return Result(path: nil, seconds: 0, error: "录音太短或失败，请重试")
        }
        recorder = nil
        self.startedAt = nil
        let seconds = max(0, min(Self.maxSeconds, Int(Date().timeIntervalSince(startedAt).rounded())))
        rec.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let path = rec.url.path
        if seconds < Self.minSeconds {
            try? FileManager.default.removeItem(atPath: path)
            return Result(path: nil, seconds: 0, error: "说话时间太短")
        }
        return Result(path: path, seconds: seconds, error: nil)
    }

    /// 取消录音（上滑取消手势）：删除文件
    func cancel() {
        guard let rec = recorder else { return }
        recorder = nil
        startedAt = nil
        rec.stop()
        try? FileManager.default.removeItem(at: rec.url)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// 大厅语音播放（对齐安卓 LobbyVoicePlayer：本地文件/远端直链都能放；同一时刻只播一条）
@MainActor
final class LobbyVoicePlayer: ObservableObject {

    static let shared = LobbyVoicePlayer()

    /// 正在播放的消息 msgId（气泡据此渲染播放态）
    @Published private(set) var playingMsgId: String?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    private init() {}

    /// 点语音气泡：播的再点一下停，否则切到这条
    func toggle(msgId: String, path: String) {
        if playingMsgId == msgId {
            stop()
            return
        }
        stop()
        let url: URL
        if path.hasPrefix("http"), let remote = URL(string: path) {
            url = remote
        } else {
            url = URL(fileURLWithPath: path)
        }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = 1.0
        player = p
        playingMsgId = msgId
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        playingMsgId = nil
    }
}
