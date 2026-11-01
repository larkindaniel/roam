import Foundation
import MapKit
import XCTest
@testable import Roam

private func member(_ handle: String) -> MemberSummary {
    MemberSummary(id: UUID(), handle: handle, displayName: handle.capitalized, avatarPath: nil)
}

private func post(_ id: UUID = UUID(), author: MemberSummary = member("author"), minutesAgo: Double, likes: Int = 0, liked: Bool = false) -> ActivityItem {
    let experience = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Place", category: .culture, locality: "Porto", region: nil,
                                       countryCode: "PT", countryName: "Portugal", latitude: 41, longitude: -8, providerPlaceID: nil,
                                       followingScore: nil, followingCount: 0, viewer: .none)
    return ActivityItem(id: id, type: .rating, author: author, experience: experience, category: .culture, scoreSnapshot: nil,
                        rankSnapshot: nil, sentimentSnapshot: nil, visitID: nil, visitDate: .unknown, note: "", media: [],
                        publishedAt: Date().addingTimeInterval(-minutesAgo * 60), likeCount: likes, commentCount: 0,
                        likedByViewer: liked, isOwn: false)
}

/// Feed/comment/notification service double with scripted outcomes and server-like receipts.
private actor SocialTestService: FeedService, NotificationService, SocialService {
    var pages: [String: Page<ActivityItem>] = [:]
    var feedOutcomes: [RoamError?] = []
    var likeOutcomes: [RoamError?] = []
    var commentOutcomes: [RoamError?] = []
    var comments: [Comment] = []
    var commentOperations: [UUID] = []
    var activities: [UUID: ActivityItem] = [:]
    var notificationPage = Page<AppNotification>.empty
    var notificationOutcomes: [RoamError?] = []
    var readIDs: [UUID] = []
    var markAllCount = 0
    var memberPages: [String: Page<MemberRow>] = [:]
    var memberRequests: [(String, String?)] = []
    var followOutcomes: [RoamError?] = []

    func setPage(_ page: Page<ActivityItem>, cursor: String?) { pages[cursor ?? "first"] = page }
    func script(feed: [RoamError?] = [], likes: [RoamError?] = [], comments: [RoamError?] = [], notifications: [RoamError?] = [], follows: [RoamError?] = []) {
        feedOutcomes += feed; likeOutcomes += likes; commentOutcomes += comments; notificationOutcomes += notifications; followOutcomes += follows
    }
    func setActivity(_ item: ActivityItem) { activities[item.id] = item }
    func setNotifications(_ page: Page<AppNotification>) { notificationPage = page }
    func setMembers(_ page: Page<MemberRow>, query: String) { memberPages[query] = page }

    private func next(_ list: inout [RoamError?]) throws { if !list.isEmpty, let error = list.removeFirst() { throw error } }

    func feed(cursor: String?) async throws -> Page<ActivityItem> { try next(&feedOutcomes); return pages[cursor ?? "first"] ?? .empty }
    func profileActivity(userID: UUID, cursor: String?) async throws -> Page<ActivityItem> { try await feed(cursor: cursor) }
    func activity(id: UUID) async throws -> ActivityItem {
        guard let item = activities[id] else { throw RoamError.unavailable }
        return item
    }
    func setLike(activityID: UUID, liked: Bool) async throws -> Bool { try next(&likeOutcomes); return liked }
    func comments(activityID: UUID, cursor: String?) async throws -> Page<Comment> { Page(items: comments, nextCursor: nil) }
    func postComment(activityID: UUID, body: String, operationID: UUID) async throws -> Comment {
        commentOperations.append(operationID)
        let existing = comments.first { $0.id == operationID }
        let comment = existing ?? Comment(id: operationID, activityID: activityID, author: member("me"), body: body, createdAt: Date(), isOwn: true)
        if existing == nil { comments.append(comment) }
        // A retryable outcome models a committed comment whose response was lost.
        try next(&commentOutcomes)
        return comment
    }
    func deleteComment(id: UUID) async throws { comments.removeAll { $0.id == id } }
    func deleteActivity(id: UUID) async throws { activities[id] = nil }

    func notifications(cursor: String?) async throws -> Page<AppNotification> { try next(&notificationOutcomes); return notificationPage }
    func unreadCount() async throws -> Int { notificationPage.items.filter(\.isUnread).count }
    func markRead(id: UUID) async throws { readIDs.append(id) }
    func markAllRead() async throws { try next(&notificationOutcomes); markAllCount += 1 }

    func friendAction(userID: UUID, action: FriendAction) async throws -> FriendState { try next(&followOutcomes); return FriendState.none.applying(action) == .none ? FriendState.received.applying(action) : FriendState.none.applying(action) }
    func incomingFriendRequests(cursor: String?) async throws -> Page<MemberRow> { memberPages["|"] ?? .empty }
    func followers(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> {
        memberRequests.append((query, cursor)); return memberPages[query + "|" + (cursor ?? "")] ?? .empty
    }
    func following(of userID: UUID, query: String, cursor: String?) async throws -> Page<MemberRow> { try await followers(of: userID, query: query, cursor: cursor) }
    func searchMembers(query: String, cursor: String?) async throws -> Page<MemberRow> { .empty }
    func setMute(userID: UUID, muted: Bool) async throws {}
    func setBlock(userID: UUID, blocked: Bool) async throws {}
    func blockedMembers() async throws -> [MemberSummary] { [] }
    func mutedMembers() async throws -> [MemberSummary] { [] }
    func report(target: ReportTarget, reason: ReportReason, text: String?, operationID: UUID) async throws -> ReportReceipt {
        ReportReceipt(id: operationID, targetKind: target.kind, reason: reason, status: "received", createdAt: Date())
    }
    func myReports() async throws -> [ReportReceipt] { [] }
}

@MainActor
final class M6SocialModelTests: XCTestCase {
    func testFeedRefreshFailureKeepsPostsAndPagingDeduplicates() async throws {
        let service = SocialTestService()
        let shared = post(minutesAgo: 5)
        await service.setPage(Page(items: [post(minutesAgo: 1), shared], nextCursor: "c1"), cursor: nil)
        await service.setPage(Page(items: [shared, post(minutesAgo: 9)], nextCursor: nil), cursor: "c1")
        let model = FeedModel(service: service, notifications: service)
        await model.refresh()
        XCTAssertEqual(model.items.count, 2)
        await service.script(feed: [.offline])
        await model.refresh()
        XCTAssertEqual(model.items.count, 2, "A failed refresh never blanks the feed")
        XCTAssertEqual(model.error, RoamError.offline.errorDescription)
        await model.loadMore()
        XCTAssertEqual(model.items.count, 3, "Paging deduplicates a post that moved between pages")
        XCTAssertNil(model.nextCursor)
    }

    func testLikeIsOptimisticAndRollsBackOnFailure() async throws {
        let service = SocialTestService()
        let item = post(minutesAgo: 1, likes: 2)
        await service.setPage(Page(items: [item], nextCursor: nil), cursor: nil)
        let model = FeedModel(service: service, notifications: service)
        await model.refresh()
        await model.setLike(item.id, liked: true)
        XCTAssertEqual(model.items.first?.likeCount, 3)
        XCTAssertEqual(model.items.first?.likedByViewer, true)
        await service.script(likes: [.offline])
        await model.setLike(item.id, liked: false)
        XCTAssertEqual(model.items.first?.likeCount, 3, "A failed unlike restores the acknowledged state")
        XCTAssertEqual(model.items.first?.likedByViewer, true)
        XCTAssertNotNil(model.actionError)
    }

    func testUnavailablePostLeavesTheFeedWhenLiking() async throws {
        let service = SocialTestService()
        let item = post(minutesAgo: 1)
        await service.setPage(Page(items: [item], nextCursor: nil), cursor: nil)
        await service.script(likes: [.unavailable])
        let model = FeedModel(service: service, notifications: service)
        await model.refresh()
        await model.setLike(item.id, liked: true)
        XCTAssertTrue(model.items.isEmpty, "A removed or blocked post does not stay on screen")
    }

    func testFailedCommentKeepsTextAndRetriesTheSameOperation() async throws {
        let service = SocialTestService()
        let item = post(minutesAgo: 1)
        await service.setActivity(item)
        await service.script(comments: [.timeout])
        let model = ActivityDetailModel(activityID: item.id, service: service)
        await model.load()
        model.draft = "See you there"
        let first = await model.post()
        XCTAssertFalse(first)
        XCTAssertEqual(model.draft, "See you there", "A failed send keeps the text")
        XCTAssertNotNil(model.pending)
        let second = await model.post()
        XCTAssertTrue(second)
        XCTAssertEqual(model.comments.map(\.body), ["See you there"], "The retried comment appears once")
        let operations = await service.commentOperations
        XCTAssertEqual(Set(operations).count, 1, "Retry reuses the original operation UUID")
        XCTAssertEqual(model.draft, "")
    }

    func testEditingAFailedCommentStartsANewOperation() async throws {
        let service = SocialTestService()
        let item = post(minutesAgo: 1)
        await service.setActivity(item)
        await service.script(comments: [.offline])
        let model = ActivityDetailModel(activityID: item.id, service: service)
        await model.load()
        model.draft = "First words"
        _ = await model.post()
        model.draft = "Better words"
        XCTAssertNil(model.pending, "Changed text is a new comment, not a retry")
        _ = await model.post()
        let operations = await service.commentOperations
        XCTAssertEqual(Set(operations).count, 2)
    }

    func testWhitespaceOnlyOrOverlongCommentsCannotBeSent() async throws {
        let service = SocialTestService()
        let item = post(minutesAgo: 1)
        await service.setActivity(item)
        let model = ActivityDetailModel(activityID: item.id, service: service)
        await model.load()
        model.draft = "   \n "
        XCTAssertFalse(model.canPost)
        model.draft = String(repeating: "a", count: 2_001)
        XCTAssertFalse(model.canPost)
        model.draft = "Fine"
        XCTAssertTrue(model.canPost)
    }

    func testUnavailablePostShowsNoCachedText() async throws {
        let service = SocialTestService()
        let model = ActivityDetailModel(activityID: UUID(), service: service)
        await model.load()
        XCTAssertTrue(model.isUnavailable)
        XCTAssertNil(model.item)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testNotificationsSplitUnreadMarkReadOnOpenAndRouteSafely() async throws {
        let service = SocialTestService()
        let actor = member("theo")
        let activity = UUID()
        let unread = AppNotification(id: UUID(), type: .comment, actor: actor, activityID: activity, experienceName: "Place",
                                     commentPreview: "Hi", createdAt: Date(), readAt: nil, targetAvailable: true)
        let gone = AppNotification(id: UUID(), type: .like, actor: actor, activityID: UUID(), experienceName: nil,
                                   commentPreview: nil, createdAt: Date(), readAt: nil, targetAvailable: false)
        let follow = AppNotification(id: UUID(), type: .follow, actor: actor, activityID: nil, experienceName: nil,
                                     commentPreview: nil, createdAt: Date().addingTimeInterval(-60), readAt: Date(), targetAvailable: true)
        await service.setNotifications(Page(items: [unread, gone, follow], nextCursor: nil))
        let model = NotificationsModel(service: service)
        await model.load()
        XCTAssertEqual(model.unread.map(\.id), [unread.id, gone.id])
        XCTAssertEqual(model.earlier.map(\.id), [follow.id])
        let route = await model.open(unread)
        XCTAssertEqual(route, .activity(activity))
        XCTAssertEqual(model.unread.map(\.id), [gone.id], "Opening marks it read")
        let none = await model.open(gone)
        XCTAssertNil(none, "A removed target never routes")
        XCTAssertEqual(model.actionError, "This is no longer available.")
        let profile = await model.open(follow)
        XCTAssertEqual(profile, .member(actor.id))
        let reads = await service.readIDs
        XCTAssertEqual(Set(reads), [unread.id, gone.id], "Already-read notifications are not re-marked")
    }

    func testMarkAllReadRollsBackOnFailure() async throws {
        let service = SocialTestService()
        let item = AppNotification(id: UUID(), type: .like, actor: member("lena"), activityID: UUID(), experienceName: nil,
                                   commentPreview: nil, createdAt: Date(), readAt: nil, targetAvailable: true)
        await service.setNotifications(Page(items: [item], nextCursor: nil))
        let model = NotificationsModel(service: service)
        await model.load()
        await service.script(notifications: [.offline])
        await model.markAllRead()
        XCTAssertEqual(model.unread.count, 1, "A failed Mark all read keeps the unread state")
        await model.markAllRead()
        XCTAssertTrue(model.unread.isEmpty)
    }

    func testMapsFrameNearbyPinsTogetherAndSpreadOutPinsByTheirDensestGroup() {
        func contains(_ region: MKCoordinateRegion, _ pin: MapPin) -> Bool {
            abs(pin.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
                && abs(pin.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
        }
        let reykjavik = MapPin(id: "a", name: "Reykjavík", category: nil, latitude: 64.1, longitude: -21.9)
        let queenstown = MapPin(id: "b", name: "Queenstown", category: nil, latitude: -45.0, longitude: 168.7)
        let oslo = MapPin(id: "c", name: "Oslo", category: nil, latitude: 59.9, longitude: 10.7)
        let nearby = try? XCTUnwrap(GlobeMapView.region(fitting: [reykjavik, oslo]))
        XCTAssertTrue(nearby.map { contains($0, reykjavik) && contains($0, oslo) } ?? false, "Places that fit are framed together")
        let spread = try? XCTUnwrap(GlobeMapView.region(fitting: [queenstown, reykjavik, oslo]))
        XCTAssertTrue(spread.map { contains($0, reykjavik) && contains($0, oslo) } ?? false, "A world-spanning set opens on its densest group")
        XCTAssertFalse(spread.map { contains($0, queenstown) } ?? true)
        let pair = try? XCTUnwrap(GlobeMapView.region(fitting: [reykjavik, queenstown]))
        XCTAssertTrue(pair.map { contains($0, reykjavik) } ?? false, "With no denser group the first place is shown, never empty ocean")
        XCTAssertNil(GlobeMapView.region(fitting: []))
    }

    func testFollowListLatestQueryWinsAndFollowRollsBack() async throws {
        let service = SocialTestService()
        let lena = MemberRow(member: member("lena"), friendState: .received, isSelf: false)
        let sam = MemberRow(member: member("sam"), friendState: .received, isSelf: false)
        await service.setMembers(Page(items: [lena, sam], nextCursor: nil), query: "|")
        await service.setMembers(Page(items: [sam], nextCursor: nil), query: "sa|")
        let model = FollowListModel(userID: UUID(), segment: .friends, service: service)
        await model.load(query: "")
        XCTAssertEqual(model.rows.count, 2)
        await model.load(query: " sa ")
        XCTAssertEqual(model.rows.map(\.id), [sam.id], "The trimmed latest query defines the rows")
        await service.script(follows: [.offline])
        await model.apply(.accept, to: sam)
        XCTAssertEqual(model.rows.first?.friendState, .received, "A failed accept rolls back")
        await model.apply(.accept, to: sam)
        XCTAssertEqual(model.rows.first?.friendState, .friends)
    }
}

final class FriendStateTests: XCTestCase {
    func testTappingTheFriendButtonFollowsTheRequestFlow() {
        XCTAssertEqual(FriendState.none.primaryAction, .request)
        XCTAssertEqual(FriendState.sent.primaryAction, .cancel)
        XCTAssertEqual(FriendState.received.primaryAction, .accept)
        XCTAssertEqual(FriendState.friends.primaryAction, .remove)
    }

    func testARequestToSomeoneWhoAlreadyAskedBecomesAFriendship() {
        XCTAssertEqual(FriendState.received.applying(.request), .friends)
        XCTAssertEqual(FriendState.none.applying(.request), .sent)
    }

    func testActionsThatDoNotFitTheStateChangeNothing() {
        XCTAssertEqual(FriendState.none.applying(.accept), .none)
        XCTAssertEqual(FriendState.sent.applying(.remove), .sent)
        XCTAssertEqual(FriendState.friends.applying(.decline), .friends)
    }
}

final class TripRulesTests: XCTestCase {
    func testATripNeedsAName() {
        XCTAssertNotNil(TripDraft(name: "   ").validationMessage)
        XCTAssertNil(TripDraft(name: "Portugal").validationMessage)
    }

    func testDatesAreOptionalButMustBeInOrder() {
        let early = LocalDate(year: 2026, month: 1, day: 1)
        let late = LocalDate(year: 2026, month: 2, day: 1)
        XCTAssertNil(TripDraft(name: "Open", startDate: nil, endDate: late).validationMessage)
        XCTAssertNil(TripDraft(name: "Ordered", startDate: early, endDate: late).validationMessage)
        XCTAssertNotNil(TripDraft(name: "Backwards", startDate: late, endDate: early).validationMessage)
    }

    func testAPlannedPlaceReadsAsPlannedUntilAVisitExists() {
        let place = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Cafe", latitude: 0, longitude: 0, followingCount: 0,
                                      viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))
        XCTAssertEqual(TripPlace(experience: place, stop: "", isPlanned: true, isVisited: false).state, .planned)
        XCTAssertEqual(TripPlace(experience: place, stop: "", isPlanned: true, isVisited: true).state, .visited)
    }
}

final class ForYouSectionsTests: XCTestCase {
    private func place(_ name: String, score: Int, friends: [String] = [], mine: Int? = nil) -> DiscoverPlace {
        let summary = ExperienceSummary(id: UUID(), placeID: UUID(), name: name, latitude: 0, longitude: 0, followingCount: friends.count,
                                        viewer: ViewerExperienceState(isBookmarked: false, myScore: mine.map(Score.init(tenths:)), hasVisits: mine != nil))
        return DiscoverPlace(experience: summary, communityScore: Score(tenths: score), communityCount: 1, friendNames: friends, coverPath: nil)
    }

    func testAPlaceNoFriendRatedIsNeverPresentedAsAFriendsFind() {
        let sections = ForYouSections(places: [place("Friend pick", score: 80, friends: ["Theo"]), place("Stranger", score: 90)])
        XCTAssertEqual(sections.friends.map(\.experience.name), ["Friend pick"])
        XCTAssertEqual(sections.highlyRated.map(\.experience.name), ["Stranger"])
    }

    func testOnlyHighlyRatedPlacesAreListed() {
        let sections = ForYouSections(places: [place("Good", score: 70), place("Middling", score: 69)])
        XCTAssertEqual(sections.highlyRated.map(\.experience.name), ["Good"])
    }

    func testAFriendsPlaceShowsEvenBelowTheThreshold() {
        XCTAssertEqual(ForYouSections(places: [place("Okay", score: 50, friends: ["Sam"])]).friends.count, 1)
    }

    func testPlacesYouAlreadyRatedAreNotRecommended() {
        let sections = ForYouSections(places: [place("Been", score: 90, friends: ["Theo"], mine: 70)])
        XCTAssertTrue(sections.friends.isEmpty && sections.highlyRated.isEmpty)
    }

    func testBestPlacesComeFirst() {
        let sections = ForYouSections(places: [place("Lower", score: 75), place("Higher", score: 95)])
        XCTAssertEqual(sections.highlyRated.map(\.experience.name), ["Higher", "Lower"])
    }

    func testFriendEvidenceNamesRealPeople() {
        XCTAssertEqual(place("A", score: 80, friends: ["Theo Park"]).friendEvidence, "Theo has been")
        XCTAssertEqual(place("A", score: 80, friends: ["Sam Rivera", "Theo Park"]).friendEvidence, "Sam and Theo have been")
        XCTAssertNil(place("A", score: 80).friendEvidence)
    }
}

final class ResearchBriefTests: XCTestCase {
    private let lisbon = Destination(name: "Lisbon", region: nil, countryCode: "PT", countryName: "Portugal", latitude: 0, longitude: 0, radiusMeters: 1)

    func testOnlyAnsweredTastesAreIncluded() {
        let text = ResearchBrief.text(destination: lisbon, taste: TasteProfile(atmosphere: "Quiet"), liked: [])
        XCTAssertTrue(text.contains("Atmosphere: Quiet"))
        XCTAssertFalse(text.contains("Budget"))
        XCTAssertFalse(text.contains("Places I've enjoyed"))
    }
}

final class DiscoverResultsTests: XCTestCase {
    private func candidate(_ name: String, isLocality: Bool) -> PlaceCandidate {
        PlaceCandidate(provider: .fixture, providerPlaceID: name, name: name, address: nil, locality: nil, region: nil, countryCode: nil, countryName: nil,
                       latitude: 0, longitude: 0, phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: nil, isLocality: isLocality, suggestedCategory: nil)
    }

    func testTownsAreNotListedAsPlaces() {
        let results = DiscoverResults(candidates: [candidate("Cafe", isLocality: false), candidate("Porto", isLocality: true)])
        XCTAssertEqual(results.places.map(\.candidate.name), ["Cafe"])
    }

    func testAKnownPlaceKeepsItsFriendData() {
        let cafe = candidate("Cafe", isLocality: false)
        let known = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Cafe", latitude: 0, longitude: 0, followingCount: 2,
                                      viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))
        XCTAssertEqual(DiscoverResults(candidates: [cafe], matches: [cafe.id: known]).places.first?.experience?.followingCount, 2)
    }

    func testNoMatchesIsEmpty() {
        XCTAssertTrue(DiscoverResults().isEmpty)
    }
}

final class DiscoverCityTests: XCTestCase {
    private func place(_ city: String?, score: Int, friends: [String] = []) -> DiscoverPlace {
        let summary = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Place", locality: city, latitude: 10, longitude: 20, followingCount: friends.count,
                                        viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))
        return DiscoverPlace(experience: summary, communityScore: Score(tenths: score), communityCount: 1, friendNames: friends, coverPath: nil)
    }

    func testPlacesGroupIntoOneCity() {
        let cities = DiscoverCity.cities(from: [place("Lisbon", score: 80), place("Lisbon", score: 90)])
        XCTAssertEqual(cities.count, 1)
        XCTAssertEqual(cities.first?.placeCount, 2)
        XCTAssertEqual(cities.first?.bestScore, Score(tenths: 90))
    }

    func testCitiesYourFriendsVisitedComeFirst() {
        let cities = DiscoverCity.cities(from: [place("Kyoto", score: 95), place("Lisbon", score: 70, friends: ["Theo Park"])])
        XCTAssertEqual(cities.map(\.destination.name), ["Lisbon", "Kyoto"])
    }

    func testPlacesWithNoCityAreLeftOut() {
        XCTAssertTrue(DiscoverCity.cities(from: [place(nil, score: 90)]).isEmpty)
    }
}

final class TripTitleTests: XCTestCase {
    private let tokyo = TripLocation(city: "Tokyo", countryCode: "JP", country: "Japan")
    private let kyoto = TripLocation(city: "Kyoto", countryCode: "JP", country: "Japan")
    private let porto = TripLocation(city: "Porto", countryCode: "PT", country: "Portugal")

    func testOneCityShowsTheCityAndFlag() {
        XCTAssertEqual(TripTitle.from([tokyo]), "Tokyo 🇯🇵")
    }

    func testSeveralCitiesInACountryShowTheCountry() {
        XCTAssertEqual(TripTitle.from([tokyo, kyoto]), "Japan 🇯🇵")
    }

    func testSeveralCountriesListEach() {
        XCTAssertEqual(TripTitle.from([tokyo, porto]), "Japan 🇯🇵 · Portugal 🇵🇹")
    }

    func testUnknownLocationsGiveNoTitle() {
        XCTAssertNil(TripTitle.from([]))
    }
}

final class SearchDedupeTests: XCTestCase {
    func testAPlaceAlreadyOnRoamIsNotListedTwice() {
        let candidate = PlaceCandidate(provider: .mapkit, providerPlaceID: "x", name: "Casa Loma", address: nil, locality: nil, region: nil, countryCode: nil, countryName: nil,
                                       latitude: 0, longitude: 0, phone: nil, website: nil, providerCategory: nil, timeZoneIdentifier: nil, isLocality: false, suggestedCategory: nil)
        let known = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Casa Loma", latitude: 0, longitude: 0, followingCount: 1,
                                      viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))
        let results = DiscoverResults(candidates: [candidate], onRoam: [known])
        XCTAssertEqual(results.onRoam.count, 1)
        XCTAssertTrue(results.places.isEmpty)
    }
}

final class TripTopPicksTests: XCTestCase {
    private let place = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Cafe", latitude: 0, longitude: 0, followingCount: 0,
                                          viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))

    private func entry(_ score: Int?, place: ExperienceSummary? = nil) -> TripFeedEntry {
        var value = place ?? self.place
        if place == nil { value = ExperienceSummary(id: UUID(), placeID: UUID(), name: "Place", latitude: 0, longitude: 0, followingCount: 0, viewer: self.place.viewer) }
        return TripFeedEntry(id: UUID(), experience: value, publicNote: "", visitDate: VisitDate(date: nil, timeZoneIdentifier: nil), media: [],
                             createdAt: Date(), score: score.map(Score.init(tenths:)), activityID: nil)
    }

    func testBestRankedVisitsComeFirstAndUnrankedOnesAreLeftOut() {
        let picks = TripText.topPicks([entry(60), entry(nil), entry(90)])
        XCTAssertEqual(picks.map(\.score?.tenths), [90, 60])
    }

    func testARepeatVisitCountsOnce() {
        XCTAssertEqual(TripText.topPicks([entry(80, place: place), entry(70, place: place)]).count, 1)
    }
}

final class PlaceMapRulesTests: XCTestCase {
    private func place(_ name: String, latitude: Double = 0, longitude: Double = 0) -> ExperienceSummary {
        ExperienceSummary(id: UUID(), placeID: UUID(), name: name, latitude: latitude, longitude: longitude, followingCount: 0, viewer: ViewerExperienceState(isBookmarked: false, hasVisits: false))
    }

    func testAPlaceGetsOneMarkerInItsMostAdvancedState() {
        let cafe = place("Cafe")
        XCTAssertEqual(PlaceMapItem.items(been: [cafe], planned: [cafe], wishlist: [cafe, place("Park")]).map(\.state), [.visited, .wishlist])
    }

    func testMarkersFollowZoomAndSelection() {
        XCTAssertEqual(PlaceMarkerStage.stage(isSelected: false, latitudeSpan: 1), .dot)
        XCTAssertEqual(PlaceMarkerStage.stage(isSelected: false, latitudeSpan: 0.01), .marker)
        XCTAssertEqual(PlaceMarkerStage.stage(isSelected: true, latitudeSpan: 1), .pin)
    }

    func testTheMapStartsOnTheLargestGroupOfPlaces() {
        let items = [place("A", latitude: 43.6, longitude: -79.4), place("B", latitude: 43.7, longitude: -79.3), place("Far", latitude: 1.3, longitude: 103.8)]
            .map { PlaceMapItem(experience: $0, state: .visited) }
        XCTAssertEqual(PlaceMapItem.startingRegion(items).center.latitude, 43.65, accuracy: 0.01)
    }
}
