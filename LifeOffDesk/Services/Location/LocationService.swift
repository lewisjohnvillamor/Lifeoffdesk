import CoreLocation
import LifeOffDeskCore

/// Thin Core Location wrapper. Tracking runs only between an explicit start and stop.
/// Created on the main thread, so delegate callbacks arrive on the main thread.
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Authorization: Equatable {
        case notDetermined, denied, restricted, authorized
    }

    var onSamples: (([TrackSample]) -> Void)?
    var onAuthorizationChange: ((Authorization) -> Void)?
    var onError: ((String) -> Void)?

    private let manager = CLLocationManager()
    private(set) var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other // adventures can be on foot or riding; .fitness assumes walking
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorization: Authorization {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .denied
        }
    }

    var hasReducedAccuracy: Bool { manager.accuracyAuthorization == .reducedAccuracy }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard authorization == .authorized else { return }
        // Background updates continue only for a walk the user started (UIBackgroundModes: location),
        // with the system location indicator visible. Behaviour must be verified on the phone.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isUpdating = true
    }

    /// One fix outside a walk (planner origin, destination distance, "you are here").
    /// GPS works without mobile data or Wi-Fi; the first fix can just take longer offline.
    func requestOneShot() {
        guard authorization == .authorized, !isUpdating else { return }
        manager.requestLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isUpdating = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(authorization)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map {
            TrackSample(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                        timestamp: $0.timestamp, horizontalAccuracy: $0.horizontalAccuracy,
                        speed: $0.speed >= 0 ? $0.speed : nil)
        }
        onSamples?(samples)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return // Transient: Core Location keeps trying.
        }
        onError?(error.localizedDescription)
    }
}
