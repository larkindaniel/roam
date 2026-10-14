import MapKit
import XCTest
@testable import Roam

private actor ExploreTestProvider: PlaceSearchProviding {
    let base: any PlaceSearchProviding
    var fails = false
    var regions: [Double] = []
    init(base: any PlaceSearchProviding) { self.base = base }
    func fail(_ value: Bool) { fails = value }
    func searchPlaces(query: String, around destination: Destination?) async throws -> [PlaceCandidate] { try await base.searchPlaces(query: query, around: destination) }
    func searchDestinations(query: String) async throws -> [Destination] { try await base.searchDestinations(query: query) }
    func destination(for coordinate: CLLocationCoordinate2D) async throws -> Destination? { try await base.destination(for: coordinate) }
    func pointsOfInterest(in region: MKCoordinateRegion, category: ExperienceCategory?) async throws -> [PlaceCandidate] {
        regions.append(region.center.latitude)
        if fails { throw RoamError.offline }
        if region.center.latitude > 40 { try await Task.sleep(for: .milliseconds(60)) }
        return try await base.pointsOfInterest(in: region, category: category)
    }
}

@MainActor
final class M3ExploreTests: XCTestCase {
    private func services() -> AppServices {
        var options = LaunchOptions()
        options.backend = .fixture
        options.fixtureAccount = "maya"
        return AppServices.make(options: options)
    }

    private func region(_ latitude: Double, _ longitude: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), latitudinalMeters: 30_000, longitudinalMeters: 30_000)
    }

    func testFailedViewportRetainsPinsAndRetryUsesFailedArea() async {
        let services = services()
        let provider = ExploreTestProvider(base: services.places)
        let model = ExploreModel(places: provider, experiences: services.experiences)
        await model.load(region: region(38.7223, -9.1393))
        let pins = model.items
        XCTAssertFalse(pins.isEmpty)
        await provider.fail(true)
        await model.load(region: region(35.0116, 135.7681))
        XCTAssertEqual(model.items, pins)
        guard case .failed = model.phase else { return XCTFail("Failure must be visible") }
        await provider.fail(false)
        await model.retry()
        XCTAssertEqual(model.loadedRegion?.center.latitude, 35.0116)
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertTrue(model.items.allSatisfy { abs($0.latitude - 35) < 1 })
        let attempts = await provider.regions
        XCTAssertEqual(attempts, [38.7223, 35.0116, 35.0116])
    }

    func testOldAreaCannotReplaceLatestViewport() async {
        let services = services()
        let provider = ExploreTestProvider(base: services.places)
        let model = ExploreModel(places: provider, experiences: services.experiences)
        async let slow: Void = model.load(region: region(51.1784, -115.5708))
        try? await Task.sleep(for: .milliseconds(10))
        await model.load(region: region(38.7223, -9.1393))
        _ = await slow
        XCTAssertEqual(model.loadedRegion?.center.latitude, 38.7223)
        XCTAssertFalse(model.items.isEmpty)
        XCTAssertTrue(model.items.allSatisfy { abs($0.latitude - 38.7) < 1 })
    }

    func testCancelledInitialLoadLeavesRetryableStateAndRecovers() async {
        let services = services()
        let provider = ExploreTestProvider(base: services.places)
        let model = ExploreModel(places: provider, experiences: services.experiences)
        let load = Task { await model.load(region: region(51.1784, -115.5708)) }
        while await provider.regions.isEmpty { await Task.yield() }
        load.cancel()
        _ = await load.value
        guard case .idle = model.phase else { return XCTFail("A cancelled initial load must not stay loading") }
        XCTAssertNil(model.loadedRegion)
        await model.retry()
        XCTAssertNotNil(model.loadedRegion)
        XCTAssertFalse(model.items.isEmpty)
    }

    func testSearchThisAreaReplacesPinsAndClearsIncompatibleSelection() async {
        let services = services()
        let model = ExploreModel(services: services)
        await model.load(region: region(38.7223, -9.1393))
        model.selectedID = model.items.first?.id
        model.visibleRegion = region(35.0116, 135.7681)
        XCTAssertTrue(model.canSearchThisArea)
        await model.searchThisArea()
        XCTAssertNil(model.selectedID)
        XCTAssertFalse(model.canSearchThisArea)
        XCTAssertTrue(model.items.allSatisfy { abs($0.latitude - 35) < 1 })
    }
}
