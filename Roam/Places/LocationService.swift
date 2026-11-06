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

@MainActor
protocol LocationManaging: AnyObject {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    func requestWhenInUseAuthorization()
    func requestLocation()
    func stopUpdatingLocation()
}

extension CLLocationManager: LocationManaging {}

/// Requests "when in use" location when the member searches or taps a location action. Never background.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager: any LocationManaging
    private var waiters: [UUID: CheckedContinuation<LocationOutcome, Never>] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var requestID: UUID?
    private let simulated: String?

    private(set) var lastOutcome: LocationOutcome?

    var isAuthorized: Bool {
        if let simulated { return simulated.hasPrefix("granted") || simulated.hasPrefix("approximate") }
        return manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    init(simulated: String? = nil, manager: any LocationManaging = CLLocationManager()) {
        self.simulated = simulated
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation(timeout: Duration = .seconds(10)) async -> LocationOutcome {
        if let simulated {
            let outcome = Self.simulatedOutcome(simulated)
            lastOutcome = outcome
            return outcome
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: .unavailable); return }
                waiters[waiterID] = continuation
                // Coalesce repeated taps without overwriting an outstanding continuation.
                guard requestID == nil else { return }
                let id = UUID()
                requestID = id
                timeoutTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.requestID == id else { return }
                    self.finish(.timedOut)
                }
                requestIfAuthorized()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let waiter = self.waiters.removeValue(forKey: waiterID) else { return }
                waiter.resume(returning: .unavailable)
                if self.waiters.isEmpty { self.stopRequest() }
            }
        }
    }

    /// Asks once for "when in use" location so searches can start near you. Does nothing after an answer.
    func requestAccessIfNeeded() {
        guard simulated == nil, manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    private func requestIfAuthorized() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied: finish(.denied)
        case .restricted: finish(.restricted)
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: finish(.unavailable)
        }
    }

    private func stopRequest() {
        timeoutTask?.cancel()
        timeoutTask = nil
        requestID = nil
        manager.stopUpdatingLocation()
    }

    private func finish(_ outcome: LocationOutcome) {
        guard requestID != nil else { return }
        let pending = waiters.values
        waiters = [:]
        stopRequest()
        lastOutcome = outcome
        for waiter in pending { waiter.resume(returning: outcome) }
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
        Task { @MainActor in
            guard self.requestID != nil, self.manager.authorizationStatus != .notDetermined else { return }
            self.requestIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            guard let location else { self.finish(.unavailable); return }
            self.finish(.located(location.coordinate, approximate: self.manager.accuracyAuthorization == .reducedAccuracy))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.unavailable) }
    }
}
