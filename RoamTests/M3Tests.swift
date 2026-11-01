import CoreLocation
import XCTest
@testable import Roam

final class ListEngineTests: XCTestCase {
    private func entry(_ name: String, category: ExperienceCategory?, city: String?, country: String?, ranked: Bool = true, rank: Int? = nil,
                       visit: String? = nil, savedDaysAgo: Double? = nil, lat: Double = 0, lon: Double = 0, firstRated: Double = 0) -> ListEntry {
        let id = UUID()
        let summary = ExperienceSummary(id: id, placeID: UUID(), name: name, category: category, locality: city, region: nil, countryCode: country,
                                        countryName: country, latitude: lat, longitude: lon, providerPlaceID: nil, followingScore: nil,
                                        followingCount: 0, viewer: .none)
        return ListEntry(experience: summary, ownerCategory: category, ownerSentiment: ranked ? .liked : nil, ownerScore: ranked ? Score(tenths: 84) : nil,
                         ownerRank: rank, ownerFirstRatedAt: Date(timeIntervalSince1970: firstRated), isRanked: ranked,
                         latestVisitDate: visit.flatMap(LocalDate.init(isoString:)), latestVisitAt: nil,
                         savedAt: savedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }, viewerSavedAt: nil,
                         cityKey: city.map { "\(country ?? "xx")||\($0.lowercased())" }, cityName: city)
    }

    func testFacetsAreOrWithinAndAcross() {
        let entries = [
            entry("Lisbon café", category: .foodDrink, city: "Lisbon", country: "PT"),
            entry("Lisbon museum", category: .culture, city: "Lisbon", country: "PT"),
            entry("Kyoto café", category: .foodDrink, city: "Kyoto", country: "JP"),
            entry("Banff trail", category: .outdoors, city: "Banff", country: "CA"),
        ]
        var filter = ListFilter()
        filter.categories = [.foodDrink, .culture]          // OR within category
        filter.countryCodes = ["PT"]                         // AND with country
        let result = ListEngine.apply(entries, kind: .want, scope: .all, filter: filter, query: "", sort: .name, reference: nil)
        XCTAssertEqual(result.map(\.experience.name), ["Lisbon café", "Lisbon museum"])
        filter.countryCodes = ["PT", "JP"]
        XCTAssertEqual(ListEngine.apply(entries, kind: .want, scope: .all, filter: filter, query: "", sort: .name, reference: nil).count, 3)
    }

    func testAllBeenHasNoScoreSortAndDefaultsToRecentVisit() {
        XCTAssertFalse(ListEngine.availableSorts(kind: .been, scope: .all).contains(.categoryRank))
        XCTAssertEqual(ListEngine.defaultSort(kind: .been, scope: .all), .recentVisit)
        XCTAssertEqual(ListEngine.defaultSort(kind: .been, scope: .category(.outdoors)), .categoryRank)
        XCTAssertEqual(ListEngine.defaultSort(kind: .want, scope: .all), .savedDate)
    }

    func testRecentVisitOrdersUnknownDatesLast() {
        let entries = [entry("Old", category: .culture, city: nil, country: nil, visit: "2024-01-01"),
                       entry("Unknown", category: .culture, city: nil, country: nil, visit: nil),
                       entry("New", category: .culture, city: nil, country: nil, visit: "2026-09-01")]
        let result = ListEngine.apply(entries, kind: .been, scope: .all, filter: ListFilter(), query: "", sort: .recentVisit, reference: nil)
        XCTAssertEqual(result.map(\.experience.name), ["New", "Old", "Unknown"])
    }

    func testCategoryRankUsesCompetitionRanksWithStableTieOrder() {
        let entries = [entry("Second tie", category: .stays, city: nil, country: nil, rank: 1, firstRated: 200),
                       entry("Third", category: .stays, city: nil, country: nil, rank: 3, firstRated: 50),
                       entry("First tie", category: .stays, city: nil, country: nil, rank: 1, firstRated: 100),
                       entry("Other category", category: .culture, city: nil, country: nil, rank: 1)]
        let result = ListEngine.apply(entries, kind: .been, scope: .category(.stays), filter: ListFilter(), query: "", sort: .categoryRank, reference: nil)
        XCTAssertEqual(result.map(\.experience.name), ["First tie", "Second tie", "Third"])
    }

    func testBeenThereShowsUnrankedPlacesAndTheFilterIsolatesThem() {
        let entries = [entry("Ranked", category: .foodDrink, city: nil, country: nil, ranked: true, rank: 1),
                       entry("Memory", category: .foodDrink, city: nil, country: nil, ranked: false)]
        XCTAssertEqual(Set(ListEngine.apply(entries, kind: .been, scope: .all, filter: ListFilter(), query: "", sort: .name, reference: nil).map(\.experience.name)), ["Ranked", "Memory"])
        var filter = ListFilter()
        filter.unrankedMemories = true
        XCTAssertEqual(ListEngine.apply(entries, kind: .been, scope: .all, filter: filter, query: "", sort: .name, reference: nil).map(\.experience.name), ["Memory"])
    }

    func testDistanceSortsNearestFirstAndMissingReferenceFallsBackToName() {
        let entries = [entry("Far", category: .culture, city: nil, country: nil, lat: 10, lon: 10),
                       entry("Near", category: .culture, city: nil, country: nil, lat: 0.1, lon: 0.1),
                       entry("Middle", category: .culture, city: nil, country: nil, lat: 2, lon: 2)]
        let reference = DistanceReference(latitude: 0, longitude: 0, source: .destination("Origin"))
        XCTAssertEqual(ListEngine.apply(entries, kind: .want, scope: .all, filter: ListFilter(), query: "", sort: .distance, reference: reference)
            .map(\.experience.name), ["Near", "Middle", "Far"])
        XCTAssertEqual(ListEngine.apply(entries, kind: .want, scope: .all, filter: ListFilter(), query: "", sort: .distance, reference: nil)
            .map(\.experience.name), ["Far", "Middle", "Near"], "Without a reference point every distance is unknown")
    }

    func testTextSearchMatchesNameAndLocalityIgnoringAccents() {
        let entries = [entry("Glass Lagoon Baths", category: .activities, city: "Reykjavík", country: "IS"),
                       entry("Aster House", category: .stays, city: "Kyoto", country: "JP")]
        XCTAssertEqual(ListEngine.apply(entries, kind: .want, scope: .all, filter: ListFilter(), query: "reykjavik", sort: .name, reference: nil).count, 1)
        XCTAssertEqual(ListEngine.apply(entries, kind: .want, scope: .all, filter: ListFilter(), query: "aster", sort: .name, reference: nil).count, 1)
    }
}

@MainActor
final class SearchRaceTests: XCTestCase {
    private func services(scenario: String = "search-race") -> AppServices {
        var options = LaunchOptions()
        options.backend = .fixture
        options.fixtureAccount = "maya"
        options.fixtureScenario = scenario
        options.resetLocalState = true
        return AppServices.make(options: options)
    }

    func testSlowOlderResponseNeverOverwritesNewerResults() async {
        let model = ExperienceSearchModel(services: services())
        // "har" is artificially delayed 1.2 s in the search-race scenario; "lantern" returns at once.
        async let slow: Void = model.search("har", near: nil)
        try? await Task.sleep(for: .milliseconds(50))
        await model.search("lantern", near: nil)
        _ = await slow
        XCTAssertEqual(model.lastQuery, "lantern")
        XCTAssertTrue(model.hits.allSatisfy { $0.candidate.name.localizedCaseInsensitiveContains("lantern") })
        XCTAssertFalse(model.hits.isEmpty)
    }

    func testCancelledSearchLeavesNoStaleState() async {
        let model = ExperienceSearchModel(services: services())
        let task = Task { await model.search("har", near: nil) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = await task.value
        XCTAssertTrue(model.hits.isEmpty)
        XCTAssertNotEqual(model.phase, .results)
    }

    func testSearchMarksExistingRoamExperiences() async {
        let model = ExperienceSearchModel(services: services(scenario: "default"))
        await model.search("harbor", near: nil)
        let harbor = model.hits.first { $0.candidate.name == "Harbor Lantern Café" }
        XCTAssertNotNil(harbor?.experience, "Existing experience matched by provider identity")
        XCTAssertEqual(harbor?.experience?.viewer.myScore, Score(tenths: 100), "Maya's score shown on the search row")
    }

    func testResolvingSameNameDifferentAddressCreatesDistinctExperiences() async throws {
        let services = services(scenario: "default")
        let model = ExperienceSearchModel(services: services)
        await model.search("morning tide", near: nil)
        XCTAssertEqual(model.hits.count, 2)
        let first = try await model.resolve(model.hits[0])
        let second = try await model.resolve(model.hits[1])
        XCTAssertNotEqual(first.id, second.id)
        let again = try await services.experiences.resolve(model.hits[0].candidate)
        XCTAssertEqual(again.id, first.id, "Re-resolving the same place returns the same experience")
    }
}

@MainActor
final class LibraryStoreTests: XCTestCase {
    private func makeServices() -> AppServices {
        var options = LaunchOptions()
        options.backend = .fixture
        options.fixtureAccount = "maya"
        options.resetLocalState = true
        return AppServices.make(options: options)
    }

    func testBookmarkIsDesiredStateAndIgnoresDuplicateTaps() async throws {
        let services = makeServices()
        let library = LibraryStore(services: services)
        await library.refresh()
        let found = try await services.places.searchPlaces(query: "Terrace Steps", around: nil)
        let candidate = try XCTUnwrap(found.first)
        let experience = try await services.experiences.resolve(candidate)
        async let first = library.setBookmark(experience.id, saved: true)
        async let duplicate = library.setBookmark(experience.id, saved: true)
        let results = await [first, duplicate]
        XCTAssertEqual(results.filter { $0 }.count, 1, "The duplicate tap is ignored while the first write is in flight")
        XCTAssertTrue(library.isBookmarked(experience.id))
        let want = try await services.lists.want(ownerID: FixtureIDs.maya)
        XCTAssertEqual(want.filter { $0.id == experience.id }.count, 1)
        let been = try await services.lists.been(ownerID: FixtureIDs.maya)
        XCTAssertFalse(been.contains { $0.id == experience.id }, "Saving creates no visit")
    }

    func testRatedExperienceCannotBeSavedAndRollsBack() async throws {
        let services = makeServices()
        let library = LibraryStore(services: services)
        await library.refresh()
        let beenList = try await services.lists.been(ownerID: FixtureIDs.maya)
        let harbor = try XCTUnwrap(beenList.first { $0.experience.name == "Harbor Lantern Café" })
        XCTAssertEqual(library.saveState(for: harbor.id), .alreadyBeen)
        let ok = await library.setBookmark(harbor.id, saved: true)
        XCTAssertFalse(ok)
        XCTAssertFalse(library.isBookmarked(harbor.id))
        XCTAssertEqual(library.lastError, RoamError.alreadyRated.errorDescription)
    }
}
