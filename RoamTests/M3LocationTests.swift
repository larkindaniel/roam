import CoreLocation
import XCTest
@testable import Roam

@MainActor
private final class SilentLocationManager: LocationManaging {
    weak var delegate: (any CLLocationManagerDelegate)?
    var desiredAccuracy: CLLocationAccuracy = 0
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var requests = 0
    var stops = 0
    func requestWhenInUseAuthorization() { requests += 1 }
    func requestLocation() { requests += 1 }
    func stopUpdatingLocation() { stops += 1 }
}

@MainActor
final class M3LocationTests: XCTestCase {
    func testRealRequestBridgeTimesOutWithoutDelegateCallback() async {
        let manager = SilentLocationManager()
        let service = LocationService(manager: manager)
        let outcome = await service.currentLocation(timeout: .milliseconds(20))
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertEqual(service.lastOutcome, .timedOut)
        XCTAssertEqual(manager.requests, 1)
        XCTAssertEqual(manager.stops, 1)
    }

    func testAuthorizationPromptAlsoHasBoundedTimeout() async {
        let manager = SilentLocationManager()
        manager.authorizationStatus = .notDetermined
        let service = LocationService(manager: manager)
        let outcome = await service.currentLocation(timeout: .milliseconds(20))
        XCTAssertEqual(outcome, .timedOut)
    }

    func testConcurrentTapsShareOneRequestAndBothComplete() async {
        let manager = SilentLocationManager()
        let service = LocationService(manager: manager)
        async let first = service.currentLocation(timeout: .milliseconds(30))
        async let second = service.currentLocation(timeout: .milliseconds(30))
        let outcomes = await [first, second]
        XCTAssertEqual(outcomes, [.timedOut, .timedOut])
        XCTAssertEqual(manager.requests, 1)
    }

    func testCancellationCompletesAndNextRequestWorks() async {
        let manager = SilentLocationManager()
        let service = LocationService(manager: manager)
        let request = Task { await service.currentLocation(timeout: .seconds(10)) }
        await Task.yield()
        request.cancel()
        let cancelled = await request.value
        XCTAssertEqual(cancelled, .unavailable)
        let next = await service.currentLocation(timeout: .milliseconds(20))
        XCTAssertEqual(next, .timedOut)
        XCTAssertEqual(manager.requests, 2)
    }

    func testDelegateSuccessUsesApproximateFlagAndIgnoresLateFailure() async {
        let manager = SilentLocationManager()
        manager.accuracyAuthorization = .reducedAccuracy
        let service = LocationService(manager: manager)
        let request = Task { await service.currentLocation(timeout: .seconds(1)) }
        await Task.yield()
        let callbackManager = CLLocationManager()
        service.locationManager(callbackManager, didUpdateLocations: [CLLocation(latitude: 38.7, longitude: -9.1)])
        let result = await request.value
        XCTAssertEqual(result, .located(CLLocationCoordinate2D(latitude: 38.7, longitude: -9.1), approximate: true))
        service.locationManager(callbackManager, didFailWithError: CLError(.locationUnknown))
        await Task.yield()
        XCTAssertEqual(service.lastOutcome, result)
    }
}
