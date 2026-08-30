import CoreLocation

/// 城市定位（对齐安卓 HomeScreen 状态行 + 广场推荐同城加分：定位城市名/坐标，拒绝/失败则静默降级）。
/// 单次定位 + CLGeocoder 反查 locality；结果进程内缓存；城市名与坐标请求共用同一次定位。
final class CityLocator: NSObject, CLLocationManagerDelegate {

    static let shared = CityLocator()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var cachedCity: String?
    private var cachedCoordinate: CLLocationCoordinate2D?
    /// 进行中的定位任务：并发调用共用，避免多路 continuation 互踩
    private var locatingTask: Task<CLLocation?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // 粗略定位即可（对齐安卓 COARSE）
    }

    /// 当前城市名（如"济南"）；未授权/失败返回 nil
    func currentCity() async -> String? {
        if let cachedCity { return cachedCity }
        guard let location = await requestLocation() else { return nil }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))
        // 直辖市 locality 为空时回退省级名
        var city = placemarks?.first?.locality ?? placemarks?.first?.administrativeArea
        city = city?.replacingOccurrences(of: "市", with: "")
        if let city { cachedCity = city }
        return city
    }

    /// 当前坐标（广场推荐流同城加分用，对齐安卓 viewerLatitude/viewerLongitude）；未授权/失败返回 nil
    func currentCoordinate() async -> (latitude: Double, longitude: Double)? {
        if let c = cachedCoordinate { return (c.latitude, c.longitude) }
        guard let location = await requestLocation() else { return nil }
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    /// 单次定位：并发共用一次请求，成功即缓存坐标
    private func requestLocation() async -> CLLocation? {
        if let task = locatingTask { return await task.value }
        let task = Task { await self.performRequest() }
        locatingTask = task
        let location = await task.value
        locatingTask = nil
        if let location { cachedCoordinate = location.coordinate }
        return location
    }

    private func performRequest() async -> CLLocation? {
        await withCheckedContinuation { cont in
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
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        let cont = continuation
        continuation = nil
        cont?.resume(returning: location)
    }
}
