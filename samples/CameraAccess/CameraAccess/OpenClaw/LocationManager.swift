import CoreLocation
import Foundation

@MainActor
class LocationManager: NSObject {
    static let shared = LocationManager()

    private let clManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastPlacemark: CLPlacemark?

    private override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        clManager.distanceFilter = 100
    }

    func requestPermissionAndStart() {
        clManager.requestWhenInUseAuthorization()
        clManager.startUpdatingLocation()
    }

    var locationContext: String? {
        if let placemark = lastPlacemark {
            let parts = [placemark.subLocality, placemark.locality, placemark.administrativeArea, placemark.isoCountryCode]
                .compactMap { $0 }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
        }
        guard let loc = lastLocation else { return nil }
        return String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.lastLocation = location
        }
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            Task { @MainActor [weak self] in
                self?.lastPlacemark = placemark
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            manager.startUpdatingLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[Location] Error: %@", error.localizedDescription)
    }
}
