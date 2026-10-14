import CoreLocation
import Foundation
import Observation

enum LocationOutcome: Equatable {
    case located(CLLocationCoordinate2D, approximate: Bool)
    case denied
    case restricted
    case timedOut
    case unavailable

    static func == (lhs: LocationOutcome, rhs: LocationOutcome) -> Bool {
        switch (lhs, rhs) {
        case let (.located(a, x), .located(b, y)): return a.latitude == b.latitude && a.longitude == b.longitude && x == y
        case (.denied, .denied), (.restricted, .restricted), (.timedOut, .timedOut), (.unavailable, .unavailable): return true
        default: return false
        }
    }

    var message: String? {
        switch self {
        case .located(_, true): return "Using your approximate location."
        case .located: return nil
        case .denied: return "Location is off for Roam. Choose a destination instead, or allow location in Settings."
        case .restricted: return "Location is restricted on this device. Choose a destination instead."
        case .timedOut: return "Couldn't find your location in time. Choose a destination instead."
        case .unavailable: return "Your location isn't available. Choose a destination instead."
        }
    }
}

/// Requests "when in use" location only when the member taps a location action. Never background.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private let simulated: String?

    private(set) var lastOutcome: LocationOutcome?

    var isAuthorized: Bool {
        if let simulated { return simulated.hasPrefix("granted") || simulated.hasPrefix("approximate") }
        return manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    init(simulated: String? = nil) {
        self.simulated = simulated
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation(timeout: Duration = .seconds(10)) async -> LocationOutcome {
        let outcome = await resolve(timeout: timeout)
        lastOutcome = outcome
        return outcome
    }

    private func resolve(timeout: Duration) async -> LocationOutcome {
        if let simulated { return Self.simulatedOutcome(simulated) }
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch status {
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedAlways, .authorizedWhenInUse: break
        default: return .unavailable
        }
        let approximate = manager.accuracyAuthorization == .reducedAccuracy
        let location: CLLocation? = await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { continuation in
                    self.locationContinuation = continuation
                    self.manager.requestLocation()
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let pending = locationContinuation {
            locationContinuation = nil
            pending.resume(returning: nil)
        }
        guard let location else { return .timedOut }
        return .located(location.coordinate, approximate: approximate)
    }

    private static func simulatedOutcome(_ value: String) -> LocationOutcome {
        switch value {
        case "denied": return .denied
        case "restricted": return .restricted
        case "timeout": return .timedOut
        default:
            let parts = value.split(separator: ":")
            let coords = parts.count > 1 ? parts[1].split(separator: ",").compactMap { Double($0) } : []
            let coordinate = coords.count == 2 ? CLLocationCoordinate2D(latitude: coords[0], longitude: coords[1])
                : CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393)
            return .located(coordinate, approximate: value.hasPrefix("approximate"))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined, let continuation = self.authorizationContinuation else { return }
            self.authorizationContinuation = nil
            continuation.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
