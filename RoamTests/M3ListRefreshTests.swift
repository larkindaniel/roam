import Foundation
import XCTest
@testable import Roam

/// Separate response queues make concurrent Been/Want loading deterministic without sleeps.
private actor ListRefreshService: ListService {
    private var beenResponses: [Result<[ListEntry], RoamError>]
    private var wantResponses: [Result<[ListEntry], RoamError>]
    private let holdFirstLoad: Bool
    private var heldBeen: CheckedContinuation<Void, Never>?
    private var heldWant: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var beenOwners: [UUID] = []
    private(set) var wantOwners: [UUID] = []

    init(been: [Result<[ListEntry], RoamError>], want: [Result<[ListEntry], RoamError>], holdFirstLoad: Bool = false) {
        beenResponses = been
        wantResponses = want
        self.holdFirstLoad = holdFirstLoad
    }

    func been(ownerID: UUID) async throws -> [ListEntry] {
        beenOwners.append(ownerID)
        guard !beenResponses.isEmpty else { throw RoamError.unavailable }
        let response = beenResponses.removeFirst()
        if holdFirstLoad && beenOwners.count == 1 {
            await withCheckedContinuation { continuation in
                heldBeen = continuation
                resumeStartedIfReady()
            }
        }
        return try response.get()
    }

    func want(ownerID: UUID) async throws -> [ListEntry] {
        wantOwners.append(ownerID)
        guard !wantResponses.isEmpty else { throw RoamError.unavailable }
        let response = wantResponses.removeFirst()
        if holdFirstLoad && wantOwners.count == 1 {
            await withCheckedContinuation { continuation in
                heldWant = continuation
                resumeStartedIfReady()
            }
        }
        return try response.get()
    }

    func waitUntilFirstLoadIsHeld() async {
        guard heldBeen == nil || heldWant == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    private func resumeStartedIfReady() {
        guard heldBeen != nil, heldWant != nil else { return }
        started?.resume()
        started = nil
    }

    func releaseFirstLoad() {
        heldBeen?.resume()
        heldWant?.resume()
        heldBeen = nil
        heldWant = nil
    }

    func library() async throws -> UserLibrary { throw RoamError.unavailable }
    func setBookmark(experienceID: UUID, saved: Bool) async throws -> Bool { throw RoamError.unavailable }
    func sharedWants(with otherUserID: UUID) async throws -> [ListEntry] { throw RoamError.unavailable }
}

@MainActor
final class M3ListRefreshTests: XCTestCase {
    private func entry(_ name: String, ranked: Bool) -> ListEntry {
        let summary = ExperienceSummary(id: UUID(), placeID: UUID(), name: name, category: .foodDrink,
                                        locality: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal",
                                        latitude: 38.7, longitude: -9.1, providerPlaceID: nil, followingScore: nil,
                                        followingCount: 0, viewer: .none)
        return ListEntry(experience: summary, ownerCategory: .foodDrink, ownerSentiment: ranked ? .liked : nil,
                         ownerScore: ranked ? Score(tenths: 84) : nil, ownerRank: ranked ? 1 : nil,
                         ownerFirstRatedAt: ranked ? Date(timeIntervalSince1970: 100) : nil, isRanked: ranked,
                         latestVisitDate: ranked ? LocalDate(isoString: "2026-01-01") : nil,
                         latestVisitAt: ranked ? Date(timeIntervalSince1970: 200) : nil,
                         savedAt: ranked ? nil : Date(timeIntervalSince1970: 300), viewerSavedAt: nil,
                         cityKey: "pt|lisboa|lisbon", cityName: "Lisbon")
    }

    func testOlderLoadCannotOverwriteNewerAcknowledgedBookmarkRefresh() async {
        let visited = entry("Visited café", ranked: true)
        let saved = entry("Newly saved café", ranked: false)
        let lists = ListRefreshService(been: [.success([]), .success([visited])],
                                       want: [.success([]), .success([saved])], holdFirstLoad: true)
        let model = PersonalListsModel(ownerID: UUID(), kind: .want, lists: lists)
        // The initial load has captured the pre-bookmark lists, then suspends both responses.
        let initialLoad = Task { await model.load() }
        await lists.waitUntilFirstLoadIsHeld()
        // A library-revision refresh after the bookmark acknowledgement completes first.
        await model.load()
        XCTAssertEqual(model.want.value, [saved])
        XCTAssertEqual(model.been.value, [visited])

        await lists.releaseFirstLoad()
        await initialLoad.value
        XCTAssertEqual(model.visibleEntries, [saved], "The late old load must not remove the acknowledged bookmark row")
        XCTAssertEqual(model.been.value, [visited], "Both lists belong to the latest refresh")
        XCTAssertNil(model.refreshError)
    }

    func testBeenRefreshFailureSurvivesSuccessfulWantAndRetryRetainsContext() async {
        let oldBeen = entry("Harbor Café", ranked: true)
        let nextBeen = entry("Harbor Terrace", ranked: true)
        let oldWant = entry("Saved café", ranked: false)
        let nextWant = entry("New saved café", ranked: false)
        let lists = ListRefreshService(been: [.success([oldBeen]), .failure(.offline), .success([oldBeen, nextBeen])],
                                       want: [.success([oldWant]), .success([nextWant]), .success([nextWant])])
        let owner = UUID()
        let model = PersonalListsModel(ownerID: owner, kind: .been, lists: lists)
        await model.load()
        model.beenScope = .category(.foodDrink)
        model.filter = ListFilter(categories: [.foodDrink], cityKeys: ["pt|lisboa|lisbon"], countryCodes: ["PT"])
        model.sort = .name
        model.query = "Harbor"
        model.showsMap = true
        let reference = DistanceReference(latitude: 38.7, longitude: -9.1, source: .destination("Lisbon"))
        model.reference = reference
        let filters = model.filter
        let sorts = model.sortOverride

        await model.load()
        XCTAssertEqual(model.refreshError, RoamError.offline.roamMessage,
                       "A successful Want response must not hide the Been refresh failure")
        XCTAssertEqual(model.been.value, [oldBeen], "Acknowledged Been rows remain available")
        XCTAssertEqual(model.want.value, [nextWant], "The successful list still receives its refreshed contents")
        XCTAssertEqual(model.visibleEntries, [oldBeen])
        XCTAssertEqual(model.filter, filters)
        XCTAssertEqual(model.sortOverride, sorts)
        XCTAssertEqual(model.query, "Harbor")
        XCTAssertEqual(model.beenScope, .category(.foodDrink))
        XCTAssertTrue(model.showsMap)
        XCTAssertEqual(model.reference, reference)

        await model.load()
        XCTAssertNil(model.refreshError)
        XCTAssertEqual(model.been.value, [oldBeen, nextBeen])
        XCTAssertEqual(model.visibleEntries, [oldBeen, nextBeen])
        XCTAssertEqual(model.filter, filters)
        XCTAssertEqual(model.sortOverride, sorts)
        XCTAssertEqual(model.query, "Harbor")
        let beenOwners = await lists.beenOwners
        let wantOwners = await lists.wantOwners
        XCTAssertEqual(beenOwners, [owner, owner, owner])
        XCTAssertEqual(wantOwners, [owner, owner, owner])
    }

    func testWantRefreshFailureRetainsAcknowledgedRowsAndControlsWhileBeenUpdates() async {
        let oldBeen = entry("Visited café", ranked: true)
        let nextBeen = entry("New visited café", ranked: true)
        let oldWant = entry("Saved Harbor Café", ranked: false)
        let nextWant = entry("Saved Harbor Terrace", ranked: false)
        let lists = ListRefreshService(been: [.success([oldBeen]), .success([nextBeen]), .success([nextBeen])],
                                       want: [.success([oldWant]), .failure(.timeout), .success([oldWant, nextWant])])
        let model = PersonalListsModel(ownerID: UUID(), kind: .want, lists: lists)
        await model.load()
        model.filter = ListFilter(categories: [.foodDrink], countryCodes: ["PT"])
        model.sort = .name
        model.query = "Harbor"
        let filters = model.filter
        let sorts = model.sortOverride

        await model.load()
        XCTAssertEqual(model.refreshError, RoamError.timeout.roamMessage)
        XCTAssertEqual(model.want.value, [oldWant])
        XCTAssertEqual(model.been.value, [nextBeen])
        XCTAssertEqual(model.visibleEntries, [oldWant])
        XCTAssertEqual(model.filter, filters)
        XCTAssertEqual(model.sortOverride, sorts)
        XCTAssertEqual(model.query, "Harbor")
        XCTAssertEqual(model.kind, .want)

        await model.load()
        XCTAssertNil(model.refreshError)
        XCTAssertEqual(model.visibleEntries, [oldWant, nextWant])
        XCTAssertEqual(model.filter, filters)
        XCTAssertEqual(model.sortOverride, sorts)
        XCTAssertEqual(model.query, "Harbor")
    }

    func testFirstBeenLoadFailureIsAnErrorAndRetryCanPopulateIt() async {
        let saved = entry("Saved café", ranked: false)
        let visited = entry("Visited café", ranked: true)
        let lists = ListRefreshService(been: [.failure(.offline), .success([visited])],
                                       want: [.success([saved]), .success([saved])])
        let model = PersonalListsModel(ownerID: UUID(), kind: .been, lists: lists)
        await model.load()
        XCTAssertNil(model.been.value, "Initial failure must not fabricate an empty successful list")
        XCTAssertEqual(model.been.errorMessage, RoamError.offline.roamMessage)
        XCTAssertEqual(model.phase.errorMessage, RoamError.offline.roamMessage)
        XCTAssertEqual(model.want.value, [saved])
        XCTAssertNil(model.refreshError, "The initial error belongs to the failing list's load phase")

        await model.load()
        XCTAssertEqual(model.visibleEntries, [visited])
        XCTAssertNil(model.phase.errorMessage)
        XCTAssertNil(model.refreshError)
    }

    func testFirstWantLoadFailureIsNotReportedAsAnEmptySavedList() async {
        let visited = entry("Visited café", ranked: true)
        let saved = entry("Saved café", ranked: false)
        let lists = ListRefreshService(been: [.success([visited]), .success([visited])],
                                       want: [.failure(.timeout), .success([saved])])
        let model = PersonalListsModel(ownerID: UUID(), kind: .want, lists: lists)
        await model.load()
        XCTAssertNil(model.want.value)
        XCTAssertEqual(model.phase.errorMessage, RoamError.timeout.roamMessage)
        XCTAssertEqual(model.been.value, [visited])
        XCTAssertNil(model.refreshError)

        await model.load()
        XCTAssertEqual(model.visibleEntries, [saved])
        XCTAssertNil(model.phase.errorMessage)
        XCTAssertNil(model.refreshError)
    }
}
