import MapKit
import Observation
import XCTest
@testable import Roam

/// Services deliberately complete stale requests after newer work, without timing sleeps.
private actor ProjectionGate<Value: Sendable> {
    private var response: CheckedContinuation<Value, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var requested = false

    func request() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            response = continuation
            requested = true
            started?.resume()
            started = nil
        }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { started = $0 }
    }

    func succeed(_ value: Value) {
        response?.resume(returning: value)
        response = nil
    }

    func fail(_ error: RoamError) {
        response?.resume(throwing: error)
        response = nil
    }
}

private actor ProjectionPlaces: PlaceSearchProviding {
    let candidates: [PlaceCandidate]
    private var nextPointsGate: ProjectionGate<[PlaceCandidate]>?
    private(set) var searches: [String] = []
    private(set) var pointsCenters: [Double] = []

    init(_ candidates: [PlaceCandidate]) { self.candidates = candidates }

    func holdNextPoints(_ gate: ProjectionGate<[PlaceCandidate]>) { nextPointsGate = gate }

    func searchPlaces(query: String, around destination: Destination?) async throws -> [PlaceCandidate] {
        searches.append(query)
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func searchDestinations(query: String) async throws -> [Destination] { [] }
    func destination(for coordinate: CLLocationCoordinate2D) async throws -> Destination? { nil }

    func pointsOfInterest(in region: MKCoordinateRegion, category: ExperienceCategory?) async throws -> [PlaceCandidate] {
        pointsCenters.append(region.center.latitude)
        if let gate = nextPointsGate {
            nextPointsGate = nil
            return try await gate.request()
        }
        let bounds = GeoBounds(region: region)
        return candidates.filter {
            bounds.contains(latitude: $0.latitude, longitude: $0.longitude)
                && (category == nil || $0.suggestedCategory == category)
        }
    }
}

private actor ProjectionExperiences: ExperienceService {
    private var summaries: [String: ExperienceSummary]
    private var nextMatchGate: ProjectionGate<[String: ExperienceSummary]>?

    init(_ summaries: [String: ExperienceSummary]) { self.summaries = summaries }
    func acknowledge(_ summaries: [String: ExperienceSummary]) { self.summaries = summaries }
    func holdNextMatches(_ gate: ProjectionGate<[String: ExperienceSummary]>) { nextMatchGate = gate }

    func matches(for candidates: [PlaceCandidate]) async throws -> [String: ExperienceSummary] {
        if let gate = nextMatchGate {
            nextMatchGate = nil
            return try await gate.request()
        }
        let ids = Set(candidates.map(\.id))
        return summaries.filter { ids.contains($0.key) }
    }

    func resolve(_ candidate: PlaceCandidate) async throws -> ExperienceSummary {
        guard let summary = summaries[candidate.id] else { throw RoamError.notFound }
        return summary
    }

    func detail(experienceID: UUID) async throws -> ExperienceDetail { throw RoamError.unavailable }

    func experiences(in bounds: GeoBounds, category: ExperienceCategory?) async throws -> [ExperienceSummary] {
        summaries.values.filter {
            bounds.contains(latitude: $0.latitude, longitude: $0.longitude)
                && (category == nil || $0.category == category)
        }
    }
}

/// Observe the queued model work, not merely the service continuation's completion.
@MainActor
private final class ProjectionObservation {
    private let predicate: () -> Bool
    private let expectation: XCTestExpectation
    private var fulfilled = false

    init(expectation: XCTestExpectation, predicate: @escaping () -> Bool) {
        self.expectation = expectation
        self.predicate = predicate
    }

    func arm() {
        guard !fulfilled else { return }
        let satisfied = withObservationTracking { predicate() } onChange: { [weak self] in
            Task { @MainActor in self?.arm() }
        }
        if satisfied {
            fulfilled = true
            expectation.fulfill()
        }
    }
}

@MainActor
final class M4ProjectionRefreshTests: XCTestCase {
    private func place(_ name: String, latitude: Double = 38.7, longitude: Double = -9.1) -> PlaceCandidate {
        PlaceCandidate(provider: .mapkit, providerPlaceID: "projection-\(name)", name: name,
                       address: "1 Test Street", locality: "Test City", region: nil,
                       countryCode: "PT", countryName: "Portugal", latitude: latitude, longitude: longitude,
                       phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: "Europe/Lisbon",
                       isLocality: false, suggestedCategory: .foodDrink)
    }

    private func summary(_ place: PlaceCandidate, number: Int, score: Int?, rank: Int? = nil,
                         category: ExperienceCategory = .foodDrink) -> ExperienceSummary {
        ExperienceSummary(id: UUID(uuidString: String(format: "30000000-0000-4000-8000-%012d", number))!,
                          placeID: UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", number))!,
                          name: place.name, category: category, locality: place.locality, region: place.region,
                          countryCode: place.countryCode, countryName: place.countryName,
                          latitude: place.latitude, longitude: place.longitude, providerPlaceID: place.providerPlaceID,
                          followingScore: Score(tenths: 84), followingCount: 2,
                          viewer: ViewerExperienceState(isBookmarked: false, myRatingCategory: score == nil ? nil : category,
                                                        myScore: score.map { Score(tenths: $0) }, myRank: rank,
                                                        hasVisits: score != nil))
    }

    private func searchModel(_ places: ProjectionPlaces, _ experiences: ProjectionExperiences) -> ExperienceSearchModel {
        ExperienceSearchModel(searchPlaces: { try await places.searchPlaces(query: $0, around: $1) },
                              matchExperiences: { try await experiences.matches(for: $0) },
                              resolvePlace: { try await experiences.resolve($0) })
    }

    private func region(_ place: PlaceCandidate) -> MKCoordinateRegion {
        MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
    }

    func testAcknowledgedRankingRefreshesExistingQueryWithoutRepeatingProviderSearch() async {
        let alpha = place("Place Alpha"), beta = place("Place Beta")
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let oldBeta = summary(beta, number: 2, score: nil)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: oldBeta])
        let model = searchModel(places, experiences)
        await model.search("place", near: nil)

        let newAlpha = summary(alpha, number: 1, score: 100, rank: 1)
        let newBeta = summary(beta, number: 2, score: 84, rank: 2)
        await experiences.acknowledge([alpha.id: newAlpha, beta.id: newBeta])
        await model.refreshMatches()

        XCTAssertEqual(model.query, "place")
        XCTAssertEqual(model.lastQuery, "place")
        XCTAssertEqual(model.hits.map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(model.hits.map(\.experience), [newAlpha, newBeta])
        XCTAssertEqual(model.phase, .results)
        XCTAssertNil(model.refreshError)
        XCTAssertFalse(model.isRefreshing)
        let searches = await places.searches
        XCTAssertEqual(searches, ["place"], "An acknowledged ranking changes enrichment, not the provider query")
    }

    func testLateOldScoreRefreshCannotReplaceNewQuery() async {
        let alpha = place("Alpha"), beta = place("Beta")
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let newBeta = summary(beta, number: 2, score: 100, rank: 1)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: newBeta])
        let model = searchModel(places, experiences)
        await model.search("alpha", near: nil)
        let gate = ProjectionGate<[String: ExperienceSummary]>()
        await experiences.holdNextMatches(gate)
        let refresh = Task { await model.refreshMatches() }
        await gate.waitUntilRequested()

        await model.search("beta", near: nil)
        await gate.succeed([alpha.id: oldAlpha])
        await refresh.value

        XCTAssertEqual(model.query, "beta")
        XCTAssertEqual(model.lastQuery, "beta")
        XCTAssertEqual(model.hits.map(\.id), [beta.id])
        XCTAssertEqual(model.hits.first?.experience, newBeta)
        XCTAssertNil(model.refreshError)
        XCTAssertFalse(model.isRefreshing)
    }

    func testLateOldScoreRefreshFailureCannotAddErrorToNewQuery() async {
        let alpha = place("Alpha"), beta = place("Beta")
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let newBeta = summary(beta, number: 2, score: 100, rank: 1)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: newBeta])
        let model = searchModel(places, experiences)
        await model.search("alpha", near: nil)
        let gate = ProjectionGate<[String: ExperienceSummary]>()
        await experiences.holdNextMatches(gate)
        let refresh = Task { await model.refreshMatches() }
        await gate.waitUntilRequested()

        await model.search("beta", near: nil)
        await gate.fail(.offline)
        await refresh.value

        XCTAssertEqual(model.hits.first?.experience, newBeta)
        XCTAssertEqual(model.phase, .results)
        XCTAssertNil(model.refreshError)
        XCTAssertFalse(model.isRefreshing)
    }

    func testAcknowledgedRankingRefreshesSelectedExplorePayloadWithoutMovingCamera() async {
        let alpha = place("Alpha")
        let old = summary(alpha, number: 1, score: 84, rank: 2)
        let places = ProjectionPlaces([alpha])
        let experiences = ProjectionExperiences([alpha.id: old])
        let model = ExploreModel(places: places, experiences: experiences)
        let loaded = region(alpha)
        await model.load(region: loaded)
        model.selectedID = old.id.uuidString
        model.focusRegion = loaded
        model.focusToken = 9
        let panned = region(place("Elsewhere", latitude: 35, longitude: 135))
        model.visibleRegion = panned

        let acknowledged = summary(alpha, number: 1, score: 100, rank: 1, category: .outdoors)
        await experiences.acknowledge([alpha.id: acknowledged])
        await model.refreshMatches()

        XCTAssertEqual(model.items.count, 1, "Matching provider and Roam entries must remain deduplicated")
        XCTAssertEqual(model.selectedID, acknowledged.id.uuidString)
        XCTAssertEqual(model.items.first?.experience, acknowledged)
        XCTAssertEqual(model.items.first?.pin.category, .outdoors)
        XCTAssertEqual(model.focusToken, 9)
        XCTAssertEqual(model.focusRegion?.center.latitude, loaded.center.latitude)
        XCTAssertEqual(model.visibleRegion?.center.latitude, panned.center.latitude)
        XCTAssertEqual(model.loadedRegion?.center.latitude, loaded.center.latitude)
        XCTAssertTrue(model.canSearchThisArea)
    }

    func testLateOldExploreRefreshCannotReplaceNewViewportOrRestoreOldSelection() async {
        let alpha = place("Alpha"), beta = place("Beta", latitude: 35, longitude: 135)
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let newBeta = summary(beta, number: 2, score: 100, rank: 1)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: newBeta])
        let model = ExploreModel(places: places, experiences: experiences)
        await model.load(region: region(alpha))
        model.selectedID = oldAlpha.id.uuidString
        let gate = ProjectionGate<[PlaceCandidate]>()
        await places.holdNextPoints(gate)
        let refresh = Task { await model.refreshMatches() }
        await gate.waitUntilRequested()

        await model.load(region: region(beta))
        await gate.succeed([alpha])
        await refresh.value

        XCTAssertEqual(model.loadedRegion?.center.latitude, beta.latitude)
        XCTAssertEqual(model.items.map(\.id), [newBeta.id.uuidString])
        XCTAssertEqual(model.items.first?.experience, newBeta)
        XCTAssertNil(model.selectedID)
        guard case .loaded = model.phase else { return XCTFail("New viewport must keep its successful phase") }
    }

    func testLateOldExploreRefreshFailureCannotPoisonNewViewport() async {
        let alpha = place("Alpha"), beta = place("Beta", latitude: 35, longitude: 135)
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let newBeta = summary(beta, number: 2, score: 100, rank: 1)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: newBeta])
        let model = ExploreModel(places: places, experiences: experiences)
        await model.load(region: region(alpha))
        let gate = ProjectionGate<[PlaceCandidate]>()
        await places.holdNextPoints(gate)
        let refresh = Task { await model.refreshMatches() }
        await gate.waitUntilRequested()

        await model.load(region: region(beta))
        await gate.fail(.offline)
        await refresh.value

        XCTAssertEqual(model.loadedRegion?.center.latitude, beta.latitude)
        XCTAssertEqual(model.items.first?.experience, newBeta)
        guard case .loaded = model.phase else { return XCTFail("A stale background error must not poison the new viewport") }
    }

    func testScoreRefreshDuringNewQueryWaitsForItsBatchThenPublishesAcknowledgedScores() async {
        let alpha = place("Alpha"), beta = place("Beta")
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let oldBeta = summary(beta, number: 2, score: 67, rank: 3)
        let acknowledgedBeta = summary(beta, number: 2, score: 100, rank: 1)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: oldBeta])
        let model = searchModel(places, experiences)
        await model.search("alpha", near: nil)
        let foregroundGate = ProjectionGate<[String: ExperienceSummary]>()
        await experiences.holdNextMatches(foregroundGate)
        let foreground = Task { await model.search("beta", near: nil) }
        await foregroundGate.waitUntilRequested()

        await experiences.acknowledge([alpha.id: oldAlpha, beta.id: acknowledgedBeta])
        await model.refreshMatches()
        await foregroundGate.succeed([beta.id: oldBeta])
        await foreground.value

        let published = expectation(description: "Queued score refresh enriches the new query")
        let observation = ProjectionObservation(expectation: published) {
            model.hits.first?.experience == acknowledgedBeta && !model.isRefreshing
        }
        observation.arm()
        await fulfillment(of: [published], timeout: 2)
        withExtendedLifetime(observation) {}

        XCTAssertEqual(model.query, "beta")
        XCTAssertEqual(model.lastQuery, "beta")
        XCTAssertEqual(model.hits.map(\.id), [beta.id])
        XCTAssertEqual(model.hits.first?.experience, acknowledgedBeta)
        XCTAssertEqual(model.phase, .results)
        XCTAssertNil(model.refreshError)
        let searches = await places.searches
        XCTAssertEqual(searches, ["alpha", "beta"], "The foreground query must neither be dropped nor fetched twice")
    }

    func testScoreRefreshDuringNewViewportWaitsThenRefreshesRequestedAreaRatherThanOldArea() async {
        let alpha = place("Alpha"), beta = place("Beta", latitude: 35, longitude: 135)
        let oldAlpha = summary(alpha, number: 1, score: 84, rank: 2)
        let oldBeta = summary(beta, number: 2, score: 67, rank: 3)
        let acknowledgedBeta = summary(beta, number: 2, score: 100, rank: 1)
        let places = ProjectionPlaces([alpha, beta])
        let experiences = ProjectionExperiences([alpha.id: oldAlpha, beta.id: oldBeta])
        let model = ExploreModel(places: places, experiences: experiences)
        await model.load(region: region(alpha))
        model.selectedID = oldAlpha.id.uuidString
        model.focusToken = 7
        model.visibleRegion = region(beta)
        let foregroundGate = ProjectionGate<[String: ExperienceSummary]>()
        await experiences.holdNextMatches(foregroundGate)
        let requested = region(beta)
        let foreground = Task { await model.load(region: requested) }
        await foregroundGate.waitUntilRequested()

        await experiences.acknowledge([alpha.id: oldAlpha, beta.id: acknowledgedBeta])
        await model.refreshMatches()
        await foregroundGate.succeed([beta.id: oldBeta])
        await foreground.value

        let published = expectation(description: "Queued score refresh enriches the requested viewport")
        let observation = ProjectionObservation(expectation: published) {
            guard case .loaded = model.phase else { return false }
            return model.items.first?.experience == acknowledgedBeta
        }
        observation.arm()
        await fulfillment(of: [published], timeout: 2)
        withExtendedLifetime(observation) {}

        XCTAssertEqual(model.loadedRegion?.center.latitude, beta.latitude)
        XCTAssertEqual(model.items.map(\.id), [acknowledgedBeta.id.uuidString])
        XCTAssertEqual(model.items.first?.experience, acknowledgedBeta)
        XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.focusToken, 7)
        XCTAssertEqual(model.visibleRegion?.center.latitude, beta.latitude)
        let centers = await places.pointsCenters
        XCTAssertEqual(centers, [alpha.latitude, beta.latitude, beta.latitude], "Background refresh must never restore the old loaded viewport")
    }
}
