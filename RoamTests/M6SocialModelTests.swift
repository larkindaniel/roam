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

    func setFollow(userID: UUID, following: Bool) async throws -> Bool { try next(&followOutcomes); return following }
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
        let lena = MemberRow(member: member("lena"), isFollowing: false, followsViewer: true, isSelf: false)
        let sam = MemberRow(member: member("sam"), isFollowing: false, followsViewer: true, isSelf: false)
        await service.setMembers(Page(items: [lena, sam], nextCursor: nil), query: "|")
        await service.setMembers(Page(items: [sam], nextCursor: nil), query: "sa|")
        let model = FollowListModel(userID: UUID(), segment: .followers, service: service)
        await model.load(query: "")
        XCTAssertEqual(model.rows.count, 2)
        await model.load(query: " sa ")
        XCTAssertEqual(model.rows.map(\.id), [sam.id], "The trimmed latest query defines the rows")
        await service.script(follows: [.offline])
        await model.setFollow(sam, following: true)
        XCTAssertEqual(model.rows.first?.isFollowing, false, "A failed follow rolls back")
        await model.setFollow(sam, following: true)
        XCTAssertEqual(model.rows.first?.isFollowing, true)
    }
}
