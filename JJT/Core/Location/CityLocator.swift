import CoreLocation

/// 城市定位（对齐安卓 HomeScreen 状态行：定位到城市名，拒绝/失败则不显示位置块）。
/// 单次定位 + CLGeocoder 反查 locality；结果进程内缓存。
final class CityLocator: NSObject, CLLocationManagerDelegate {

    static let shared = CityLocator()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<String?, Never>?
    private var cachedCity: String?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // 粗略定位即可（对齐安卓 COARSE）
    }

    /// 当前城市名（如"济南"）；未授权/失败返回 nil
    func currentCity() async -> String? {
        if let cachedCity { return cachedCity }
        return await withCheckedContinuation { cont in
            continuation = cont
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(nil)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if continuation != nil { manager.requestLocation() }
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { finish(nil); return }
        CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN")) { [weak self] placemarks, _ in
            guard let self else { return }
            var city = placemarks?.first?.locality
            // 直辖市 locality 为空时回退省级名
            if city == nil { city = placemarks?.first?.administrativeArea }
            city = city?.replacingOccurrences(of: "市", with: "")
            if let city { self.cachedCity = city }
            self.finish(city)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ city: String?) {
        let cont = continuation
        continuation = nil
        cont?.resume(returning: city)
    }
}
