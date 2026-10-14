import MapKit
import XCTest
@testable import Roam

/// Live MapKit feasibility checks (network). Run with TEST_RUNNER_ROAM_LIVE_MAPKIT=1;
/// otherwise skipped (and reported as skipped, not passed).
final class MapKitFeasibilityTests: XCTestCase {
    private let provider = MapKitPlaceSearchProvider()

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ROAM_LIVE_MAPKIT"] == "1", "Live MapKit checks need ROAM_LIVE_MAPKIT=1")
    }

    func testResolvesRealPointOfInterestWithStableIdentifier() async throws {
        let sanFrancisco = Destination(name: "San Francisco", region: "California", countryCode: "US", countryName: "United States",
                                       latitude: 37.7749, longitude: -122.4194, radiusMeters: 15_000)
        let results = try await provider.searchPlaces(query: "Golden Gate Park", around: sanFrancisco)
        let park = try XCTUnwrap(results.first { $0.name.localizedCaseInsensitiveContains("Golden Gate Park") })
        print("ROAM-FEASIBILITY POI name=\(park.name) id=\(park.providerPlaceID ?? "nil") category=\(park.providerCategory ?? "nil") suggested=\(park.suggestedCategory?.rawValue ?? "nil") locality=\(park.locality ?? "nil") region=\(park.region ?? "nil") country=\(park.countryCode ?? "nil") tz=\(park.timeZoneIdentifier ?? "nil") address=\(park.address ?? "nil")")
        XCTAssertNotNil(park.providerPlaceID, "iOS 18+ MKMapItem.identifier should be available for POIs")
        // A second search must yield the same identifier (stable provider identity).
        let again = try await provider.searchPlaces(query: "Golden Gate Park", around: sanFrancisco)
        XCTAssertTrue(again.contains { $0.providerPlaceID == park.providerPlaceID })
        // Identifier round-trip through MKMapItemRequest.
        if let raw = park.providerPlaceID, let identifier = MKMapItem.Identifier(rawValue: raw) {
            let item = try await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
            XCTAssertEqual(item.identifier?.rawValue, raw)
        }
    }

    func testResolvesLocalityAsDayTripDestination() async throws {
        let results = try await provider.searchPlaces(query: "Hakone", around: nil)
        let locality = try XCTUnwrap(results.first { $0.isLocality })
        print("ROAM-FEASIBILITY LOCALITY name=\(locality.name) id=\(locality.providerPlaceID ?? "nil") locality=\(locality.locality ?? "nil") region=\(locality.region ?? "nil") country=\(locality.countryCode ?? "nil") suggested=\(locality.suggestedCategory?.rawValue ?? "nil")")
        XCTAssertEqual(locality.suggestedCategory, .dayTrips)
        XCTAssertEqual(locality.countryCode, "JP")
        let destinations = try await provider.searchDestinations(query: "Portland")
        print("ROAM-FEASIBILITY DESTINATIONS \(destinations.map(\.displayName))")
        XCTAssertGreaterThan(Set(destinations.compactMap(\.region)).count, 0)
    }
}
