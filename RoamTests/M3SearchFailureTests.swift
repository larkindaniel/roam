import Foundation
import XCTest
@testable import Roam

/// Explicit gates emulate services that complete after cancellation; no timing sleeps are needed.
@MainActor
private final class SearchResponseGate<Value> {
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

    func fail(_ error: Error) {
        response?.resume(throwing: error)
        response = nil
    }
}

@MainActor
final class M3SearchFailureTests: XCTestCase {
    private func candidate(_ name: String) -> PlaceCandidate {
        PlaceCandidate(provider: .mapkit, providerPlaceID: "I-\(name)", name: name, address: "1 Test Street", locality: "Lisbon",
                       region: "Lisboa", countryCode: "PT", countryName: "Portugal", latitude: 38.7, longitude: -9.1,
                       phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: nil, isLocality: false,
                       suggestedCategory: .foodDrink)
    }

    private func summary(_ candidate: PlaceCandidate) -> ExperienceSummary {
        ExperienceSummary(id: UUID(), placeID: UUID(), name: candidate.name, category: .foodDrink, locality: candidate.locality,
                          region: candidate.region, countryCode: candidate.countryCode, countryName: candidate.countryName,
                          latitude: candidate.latitude, longitude: candidate.longitude, providerPlaceID: candidate.providerPlaceID,
                          followingScore: Score(tenths: 84), followingCount: 1,
                          viewer: ViewerExperienceState(isBookmarked: true, myRatingCategory: nil, myScore: nil, myRank: nil, hasVisits: false))
    }

    private func member(_ handle: String) -> MemberRow {
        MemberRow(member: MemberSummary(id: UUID(), handle: handle, displayName: handle, avatarPath: nil),
                  friendState: .none, isSelf: false)
    }

    private func experienceModel(search: @escaping (String, Destination?) async throws -> [PlaceCandidate],
                                 matches: @escaping ([PlaceCandidate]) async throws -> [String: ExperienceSummary] = { _ in [:] }) -> ExperienceSearchModel {
        ExperienceSearchModel(searchPlaces: search, matchExperiences: matches, resolvePlace: { _ in throw RoamError.unavailable })
    }

    private func memberModel(search: @escaping (String, String?) async throws -> Page<MemberRow>) -> MemberSearchModel {
        MemberSearchModel(searchMembers: search, friendAction: { _, action in FriendState.none.applying(action) })
    }

    func testInitialEnrichmentFailureIsAnErrorRatherThanUnratedResults() async {
        let place = candidate("Harbor")
        let model = experienceModel(search: { _, _ in [place] }, matches: { _ in throw RoamError.sessionExpired })
        await model.search("harbor", near: nil)
        XCTAssertEqual(model.phase, .failed(RoamError.sessionExpired.roamMessage))
        XCTAssertTrue(model.hits.isEmpty, "Failed account-state loading must not imply the place is unrated or unsaved")
        XCTAssertFalse(model.isRefreshing)
    }

    func testEnrichmentRefreshFailureKeepsScoresAndSavedStateThenRetryRecovers() async {
        let place = candidate("Harbor")
        let existing = summary(place)
        var fails = false
        let model = experienceModel(search: { _, _ in [place] }, matches: { _ in
            if fails { throw RoamError.offline }
            return [place.id: existing]
        })
        await model.search("harbor", near: nil)
        fails = true
        await model.search("harbor", near: nil)
        XCTAssertEqual(model.phase, .results)
        XCTAssertEqual(model.hits.first?.experience, existing)
        XCTAssertEqual(model.refreshError, RoamError.offline.roamMessage)
        fails = false
        await model.search("harbor", near: nil)
        XCTAssertNil(model.refreshError)
        XCTAssertEqual(model.hits.first?.experience?.viewer.isBookmarked, true)
    }

    func testPlaceProviderRefreshFailureKeepsCurrentResultsAndQuery() async {
        let place = candidate("Harbor")
        let model = experienceModel(search: { text, _ in
            if text == "offline" { throw RoamError.offline }
            return [place]
        })
        await model.search("harbor", near: nil)
        await model.search("offline", near: nil)
        XCTAssertEqual(model.phase, .results)
        XCTAssertEqual(model.hits.map(\.candidate.name), ["Harbor"])
        XCTAssertEqual(model.query, "offline")
        XCTAssertEqual(model.lastQuery, "harbor")
        XCTAssertNotNil(model.refreshError)
    }

    func testCancelledEnrichmentCannotPublishLateAccountState() async {
        let gate = SearchResponseGate<[String: ExperienceSummary]>()
        let place = candidate("Old")
        let model = experienceModel(search: { _, _ in [place] }, matches: { _ in try await gate.request() })
        let old = Task { await model.search("old", near: nil) }
        await gate.waitUntilRequested()
        old.cancel()
        gate.succeed([place.id: summary(place)])
        await old.value
        XCTAssertTrue(model.hits.isEmpty)
        XCTAssertNotEqual(model.phase, .results)
        XCTAssertFalse(model.isRefreshing)
    }

    func testChangedQueryInvalidatesOldResponseBeforeDebouncedRequestStarts() async {
        let gate = SearchResponseGate<[PlaceCandidate]>()
        let model = experienceModel(search: { _, _ in try await gate.request() })
        let old = Task { await model.search("old", near: nil) }
        await gate.waitUntilRequested()
        model.query = "new" // The view has not yet completed its 300 ms debounce.
        gate.succeed([candidate("Old")])
        await old.value
        XCTAssertTrue(model.hits.isEmpty)
        XCTAssertEqual(model.query, "new")
        XCTAssertEqual(model.lastQuery, "")
    }

    func testNewDestinationWinsWhenOldProviderIgnoresCancellation() async {
        let gate = SearchResponseGate<[PlaceCandidate]>()
        let lisbon = Destination(name: "Lisbon", region: "Lisboa", countryCode: "PT", countryName: "Portugal",
                                 latitude: 38.7, longitude: -9.1, radiusMeters: 10_000)
        let kyoto = Destination(name: "Kyoto", region: "Kyoto", countryCode: "JP", countryName: "Japan",
                                latitude: 35.0, longitude: 135.7, radiusMeters: 10_000)
        let latest = candidate("Kyoto place")
        let model = experienceModel(search: { _, destination in
            if destination?.id == lisbon.id { return try await gate.request() }
            return [latest]
        })
        let old = Task { await model.search("cafe", near: lisbon) }
        await gate.waitUntilRequested()
        await model.search("cafe", near: kyoto)
        gate.succeed([candidate("Lisbon place")])
        await old.value
        XCTAssertEqual(model.hits.map(\.candidate.name), [latest.name])
    }

    func testOldMemberPageCannotAppendToNewQueryOrReplaceItsCursor() async {
        let gate = SearchResponseGate<Page<MemberRow>>()
        let a = member("a_first"), stale = member("a_stale"), b = member("b_first")
        let model = memberModel { query, cursor in
            if cursor != nil { return try await gate.request() }
            return Page(items: query == "a" ? [a] : [b], nextCursor: query == "a" ? "a_page2" : "b_page2")
        }
        await model.search("a")
        let old = Task { await model.loadMore() }
        await gate.waitUntilRequested()
        await model.search("b")
        gate.succeed(Page(items: [stale], nextCursor: "a_page3"))
        await old.value
        XCTAssertEqual(model.rows.map(\.id), [b.id])
        XCTAssertEqual(model.nextCursor, "b_page2")
        XCTAssertFalse(model.loadingMore)
        XCTAssertNil(model.pageError)
    }

    func testClearingQueryDropsPendingMemberPageImmediately() async {
        let gate = SearchResponseGate<Page<MemberRow>>()
        let first = member("first"), stale = member("stale")
        let model = memberModel { _, cursor in
            if cursor != nil { return try await gate.request() }
            return Page(items: [first], nextCursor: "page2")
        }
        await model.search("people")
        let old = Task { await model.loadMore() }
        await gate.waitUntilRequested()
        model.query = ""
        gate.succeed(Page(items: [stale], nextCursor: "page3"))
        await old.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.nextCursor)
        if case .idle = model.phase {} else { XCTFail("Cleared search must show its idle state") }
        XCTAssertFalse(model.loadingMore)
    }

    func testOldPaginationFailureDoesNotContaminateNewSearch() async {
        let gate = SearchResponseGate<Page<MemberRow>>()
        let a = member("a_first"), b = member("b_first")
        let model = memberModel { query, cursor in
            if cursor != nil { return try await gate.request() }
            return Page(items: query == "a" ? [a] : [b], nextCursor: "page2")
        }
        await model.search("a")
        let old = Task { await model.loadMore() }
        await gate.waitUntilRequested()
        await model.search("b")
        gate.fail(RoamError.offline)
        await old.value
        XCTAssertEqual(model.rows.map(\.id), [b.id])
        XCTAssertNil(model.pageError)
        XCTAssertNil(model.refreshError)
    }

    func testMemberPageFailureRetainsRowsAndCursorThenDeduplicatesRetry() async {
        let first = member("first"), second = member("second")
        var fails = true
        let model = memberModel { _, cursor in
            guard cursor != nil else { return Page(items: [first], nextCursor: "page2") }
            if fails { throw RoamError.timeout }
            return Page(items: [first, second, second], nextCursor: nil)
        }
        await model.search("people")
        await model.loadMore()
        XCTAssertEqual(model.rows.map(\.id), [first.id])
        XCTAssertEqual(model.nextCursor, "page2")
        XCTAssertEqual(model.pageError, RoamError.timeout.roamMessage)
        fails = false
        await model.loadMore()
        XCTAssertEqual(model.rows.map(\.id), [first.id, second.id])
        XCTAssertNil(model.pageError)
        XCTAssertNil(model.nextCursor)
    }

    func testMemberRefreshFailureRetainsRowsAndCursorForSameQuery() async {
        let first = member("first")
        var fails = false
        let model = memberModel { _, _ in
            if fails { throw RoamError.offline }
            return Page(items: [first], nextCursor: "page2")
        }
        await model.search("people")
        fails = true
        await model.search("people")
        XCTAssertEqual(model.rows.map(\.id), [first.id])
        XCTAssertEqual(model.nextCursor, "page2")
        XCTAssertEqual(model.refreshError, RoamError.offline.roamMessage)
        if case .loaded = model.phase {} else { XCTFail("Refresh error must keep the populated state") }
        fails = false
        await model.search("people")
        XCTAssertNil(model.refreshError)
    }

    func testChangedMemberQueryRejectsOldFirstPageDuringDebounce() async {
        let gate = SearchResponseGate<Page<MemberRow>>()
        let model = memberModel { _, _ in try await gate.request() }
        let old = Task { await model.search("old") }
        await gate.waitUntilRequested()
        model.query = "new"
        gate.succeed(Page(items: [member("old_member")], nextCursor: "old_page2"))
        await old.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.nextCursor)
        XCTAssertEqual(model.query, "new")
    }

    func testCancelledMemberFirstPageDoesNotPublishResults() async {
        let gate = SearchResponseGate<Page<MemberRow>>()
        let model = memberModel { _, _ in try await gate.request() }
        let request = Task { await model.search("people") }
        await gate.waitUntilRequested()
        request.cancel()
        gate.succeed(Page(items: [member("late_member")], nextCursor: "page2"))
        await request.value
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.nextCursor)
        XCTAssertFalse(model.isRefreshing)
    }

    func testFailedFollowRollsBackWithoutCreatingPaginationFailure() async {
        let first = member("first")
        let model = MemberSearchModel(searchMembers: { _, _ in Page(items: [first], nextCursor: nil) },
                                      friendAction: { _, _ in throw RoamError.offline })
        await model.search("first")
        await model.toggleFollow(first)
        XCTAssertEqual(model.rows.first?.friendState, FriendState.none)
        XCTAssertTrue(model.pendingFollows.isEmpty)
        XCTAssertEqual(model.followError, RoamError.offline.roamMessage)
        XCTAssertNil(model.pageError, "A follow failure must not offer a nonfunctional Load more retry")
    }
}
