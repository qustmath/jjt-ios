import CoreLocation
import Foundation

/// 入座/定位心跳用的一次性 GPS 采集（对齐安卓 LocationHelper：权限检查 + 8 秒超时单次定位）。
/// 坐标是「动作瞬间一次性证据」（入座三门槛之地理围栏由服务端判定）。
final class LobbyLocator: NSObject, CLLocationManagerDelegate {

    static let shared = LobbyLocator()

    /// 单次定位超时（对齐安卓 getCurrentFix 的 8s）
    static let timeoutSeconds: UInt64 = 8

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var waitingAuthorization = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    static func hasPermission() -> Bool {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// 当前一次 GPS 定位（未授权返回 nil，不弹授权弹窗——授权引导由调用方负责）；并发调用共用一次请求
    func currentFix() async -> CLLocation? {
        if continuation != nil { return nil } // 已有请求在途，直接放弃（8s 内会结束）
        return await withCheckedContinuation { cont in
            continuation = cont
            waitingAuthorization = false
            switch CLLocationManager.authorizationStatus() {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .notDetermined:
                waitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            default:
                resume(with: nil)
            }
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.timeoutSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.resume(with: nil)
            }
        }
    }

    private func resume(with location: CLLocation?) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        cont.resume(returning: location)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        resume(with: locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(with: nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard waitingAuthorization else { return }
        waitingAuthorization = false
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            resume(with: nil)
        }
    }
}
